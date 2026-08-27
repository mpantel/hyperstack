// React SSR (#18/#19): react-dom/server.browser references Web/Node platform
// APIs at module-load time that the prerender bundle's mini_racer/V8 isolate
// (bare V8) lacks — TextEncoder/TextDecoder (React 18) and MessageChannel
// (React 19 scheduler) — so the import throws `ReferenceError: <API> is not
// defined`. Imported first in react_server_runtime.js so these are installed
// before React's module body runs. TextEncoder/TextDecoder are UTF-8 only; each
// polyfill is guarded, so it is a no-op where the platform already provides it.
if (typeof globalThis.TextEncoder === "undefined") {
  globalThis.TextEncoder = class TextEncoder {
    get encoding() { return "utf-8"; }
    encode(input) {
      var str = String(input === undefined ? "" : input);
      var bytes = [];
      for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i);
        if (c < 0x80) {
          bytes.push(c);
        } else if (c < 0x800) {
          bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
        } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
          var c2 = str.charCodeAt(i + 1);
          if (c2 >= 0xdc00 && c2 <= 0xdfff) {
            c = 0x10000 + ((c & 0x3ff) << 10) + (c2 & 0x3ff);
            i++;
            bytes.push(
              0xf0 | (c >> 18),
              0x80 | ((c >> 12) & 0x3f),
              0x80 | ((c >> 6) & 0x3f),
              0x80 | (c & 0x3f)
            );
          } else {
            bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
          }
        } else {
          bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
        }
      }
      return new Uint8Array(bytes);
    }
  };
}

if (typeof globalThis.TextDecoder === "undefined") {
  globalThis.TextDecoder = class TextDecoder {
    get encoding() { return "utf-8"; }
    decode(input) {
      if (input == null) return "";
      var bytes = input instanceof Uint8Array ? input : new Uint8Array(input.buffer || input);
      var str = "";
      var i = 0;
      while (i < bytes.length) {
        var c = bytes[i++];
        if (c < 0x80) {
          str += String.fromCharCode(c);
        } else if (c < 0xe0) {
          str += String.fromCharCode(((c & 0x1f) << 6) | (bytes[i++] & 0x3f));
        } else if (c < 0xf0) {
          str += String.fromCharCode(
            ((c & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f)
          );
        } else {
          var cp =
            ((c & 0x07) << 18) |
            ((bytes[i++] & 0x3f) << 12) |
            ((bytes[i++] & 0x3f) << 6) |
            (bytes[i++] & 0x3f);
          cp -= 0x10000;
          str += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
        }
      }
      return str;
    }
  };
}

// React 19 (#19): react-dom/server's scheduler instantiates a MessageChannel at
// module-load time to schedule async work. The synchronous string renderers
// (renderToString/renderToStaticMarkup) complete within the call and never pump
// the channel, so a no-op port pair is sufficient — it only has to exist so the
// module body doesn't throw `MessageChannel is not defined` in the bare V8
// isolate. (A real browser already provides MessageChannel, so this is guarded.)
if (typeof globalThis.MessageChannel === "undefined") {
  var noop = function () {};
  var makePort = function () {
    return {
      onmessage: null,
      postMessage: noop,
      addEventListener: noop,
      removeEventListener: noop,
      start: noop,
      close: noop,
    };
  };
  globalThis.MessageChannel = class MessageChannel {
    constructor() {
      this.port1 = makePort();
      this.port2 = makePort();
    }
  };
}
