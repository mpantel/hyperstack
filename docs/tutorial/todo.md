# TodoMVC Tutorial Part I

## Prerequisites

* Linux or Mac system  

  \(Android, ChromeOS and Windows are not supported\)

* Ruby on Rails must be installed: [https://rubyonrails.org/](https://rubyonrails.org/)
* NodeJS must be installed: [https://nodejs.org](https://nodejs.org)
* Yarn must be installed: [https://yarnpkg.com/en/docs/install](https://yarnpkg.com/en/docs/install)

## The goals of this tutorial

In this tutorial, you will build the classic [TodoMVC](http://todomvc.com) application using Hyperstack. This tutorial will demonstrate several key Hyperstack concepts - client side Components and Isomorphic Models.

The finished application will

1. have the ability to add and edit todos;
2. be able change the complete/incomplete state;
3. filter the list of displayed todos to show all, complete, or incomplete \(active\) todos;
4. have html5 history so that as the filter changes so does the URL;
5. have server side persistence;
6. and synchronization across multiple browser windows.

You will write less than 100 lines of code, and the tutorial should take about 1-2 hours to complete.

## Skills required

Basic knowledge of Ruby is needed, knowledge of Ruby on Rails is helpful.

## Chapter 1: Setting Things Up

First you need to create a new project for this tutorial.

```text
rails new todo-demo --skip-test
```

This command will create a new Rails project.

**Caution:** _you can name the app anything you want, we recommend todo-demo, but whatever you do DON'T call it todo, as this name will be needed later!_

Now

```text
cd todo-demo
```

which will change the working directory to your new todo rails project.

Now run

```text
bundle add 'rails-hyperstack' --version "~> 1.0.alpha1.0"
```

which will install the `rails-hyperstack` 'gem' into the system.

Once the gem is installed run

```text
bundle exec rails hyperstack:install
```

to complete the hyperstack installation.

Finally find the `config/initializers/hyperstack.rb` file, and make sure that this line is **not** commented out:

```ruby
Hyperstack.import 'hyperstack/component/jquery', client_only: true
```

> Ignore any comments saying that it should be commented out, this is a typo in the current installer

### Start the Rails app

In the console run the following command to start the Rails server and Hotloader.

```text
bundle exec foreman start
```

For the rest of the tutorial you will want to keep foreman running in the background and have a second console window open in the `todo-demo` directory to execute various commands.

Navigate to [http://localhost:5000/](http://localhost:5000/) in your browser and you should see the word **Hello world from Hyperstack!** displayed on the page. Hyperstack will need a moment to start and pre-compile with the first request.

**Note:** _you will be using port 5000 not the more typical 3000, this is because of the way the Hotloader is configured._

### Make a Simple Change

Bring up your favorite editor on the `todo-demo` directory. You will see folders like `app`, `bin`, `config` and `db`. These have all been preinitialized by Rails and Hyperstack gems.

Now find the `app/hyperstack/components/app.rb` file. It looks like this:

```ruby
# app/hyperstack/component/app.rb

# This is your top level component, the rails router will
# direct all requests to mount this component.  You may
# then use the Route psuedo component to mount specific
# subcomponents depending on the URL.

class App < HyperComponent
  include Hyperstack::Router

  # define routes using the Route psuedo component.  Examples:
  # Route('/foo', mounts: Foo)                : match the path beginning with /foo and mount component Foo here
  # Route('/foo') { Foo(...) }                : display the contents of the block
  # Route('/', exact: true, mounts: Home)     : match the exact path / and mount the Home component
  # Route('/user/:id/name', mounts: UserName) : path segments beginning with a colon will be captured in the match param
  # see the hyper-router gem documentation for more details

  render do
    H1 { "Hello world from Hyperstack!" }
  end
end
```

Change the string displayed to something like: `"Todo App Coming Soon"`. You will see the display instantly change when you save the file.

You can also delete the comments as we will go over details of routing later.

> The Hyperstack UI is built from components. Each component is defined by a subclass of HyperComponent. In some cases there will only be one instance of the class displayed, and as we will see at other times the class is reused to display multiple components. If you are familiar with Rails or the MVC structure then you can think of Components as views that continuously update as the state of the application changes.

## Chapter 2:  Hyperstack Models are Rails Models

We are going to add our Todo Model, and discover that Hyperstack models are in fact Rails ActiveRecord models.

* You can access your rails models on the client using the same syntax you use on the server.
* Changes on the client are mirrored on the server.
* Changes to models on the server are synchronized with all participating browsers.
* Data access is protected by a robust _policy_ mechanism.

> A Rails ActiveRecord Model is a Ruby class that is backed by a database table. In this example we will have one model class called `Todo`. When manipulating models, Rails automatically generates the necessary SQL code for you. So when `Todo.all` is evaluated Rails generates the appropriate SQL and turns the result of the query into appropriate Ruby data structures.

**Hyperstack Models are extensions of ActiveRecord Models that synchronize the data between the client and server automatically for you. So now `Todo.all` can be evaluated on the server or the client.**

Okay lets see it in action:

1. **Add the Todo Model:**

As stated earlier we keep _foreman_ running in the first console and open a second console. In this second console window run **on a single line**:

```text
bundle exec rails g model Todo title:string completed:boolean priority:integer
```

This runs a Rails _generator_ which will create the skeleton Todo model class, and create a _migration_ which will add the necessary tables and columns to the database.

Now look in the db/migrate/ directory, and edit the migration file you have just created. The file will be titled with a long string of numbers then "create\_todos" at the end. Change the line creating the completed boolean field so that it looks like this:

```ruby
...
t.boolean :completed, null: false, default: false
...
```

For details on 'why' see [this blog post.](https://robots.thoughtbot.com/avoid-the-threestate-boolean-problem) Basically this insures `completed` is treated as a real boolean, and will avoid having to check between `false` and `null` later on.

Now run:

```text
bundle exec rails db:migrate
```

which will create the table.

1. **Make Your Model Public:**

Move `models/todo.rb` to `hyperstack/models`

This will make the model accessible on the clients _and the server_, subject to any data access policies.

**Note:** _The hyperstack installer adds a policy that gives full permission to all clients but only in development and test modes. Have a look at `app/policies/application_policy` if you are interested._

1. **Try It:**

Now change your `App` component's render method to:

```ruby
class App < HyperComponent
  include Hyperstack::Router
  render do
    H1 { "Number of Todos: #{Todo.count}" }
  end
end
```

You will now see **Number of Todos: 0** displayed.

Now start a rails console

```text
bundle exec rails c
```

and type:

```ruby
Todo.create(title: 'my first todo')
```

This will create a new Todo in the server's database, which will cause your Hyperstack application to be updated and you will see the count change to 1!

Try it again:

```ruby
Todo.create(title: 'my second todo')
```

and you will see the count change to 2!

Are we having fun yet? I hope so! As you can see Hyperstack is synchronizing the Todo model between the client and server. As the state of the database changes, Hyperstack buzzes around updating whatever parts of the DOM were dependent on that data \(in this case the count of Todos\).

Notice that we did not create any APIs to achieve this. Data on the server is synchronized with data on the client for you.

## Chapter 3: Creating the Top Level App Structure

Now that we have all of our pieces in place, lets build our application.

Replace the entire contents of `app.rb` with:

```ruby
# app/hyperstack/components/app.rb
class App < HyperComponent
  include Hyperstack::Router
  render(SECTION) do
    Header()
    Index()
    Footer()
  end
end
```

After saving you will see the following error displayed:

**Uncaught error: Header: undefined method \`Header' for \#\ in App \(created by Hyperstack::Internal::Component::TopLevelRailsComponent\) in Hyperstack::Internal::Component::TopLevelRailsComponent**

because we have not defined the three subcomponents. Lets define them now:

Add three new ruby files to the `app/hyperstack/components` folder:

```ruby
# app/hyperstack/components/header.rb
class Header < HyperComponent
  render(HEADER) do
    'Header will go here'
  end
end
```

```ruby
# app/hyperstack/components/index.rb
class Index < HyperComponent
  render(SECTION) do
    'List of Todos will go here'
  end
end
```

```ruby
# app/hyperstack/components/footer.rb
class Footer < HyperComponent
  render(DIV) do
    'Footer will go here'
  end
end
```

Once you add the Footer component you should see:

Header will go here List of Todos will go here Footer will go here &lt;/div&gt;   


If you don't, restart the server \(_foreman_ in the first console\), and reload the browser.

Notice how the usual HTML tags such as DIV, SECTION, and HEADER are all available as well as all the other HTML and SVG tags.

> Hyperstack uses the following conventions to easily distinguish between HTML tags, application defined components and other helper methods:
>
> * HTML tags are in all caps
> * Application components are CamelCased
> * other helper methods are snake\_cased

## Chapter 4: Listing the Todos, Hyperstack Params, and Prerendering

To display each Todo we will create a TodoItem component that takes a parameter:

```ruby
# app/hyperstack/components/todo_item.rb
class TodoItem < HyperComponent
  param :todo
  render(LI) do
    todo.title
  end
end
```

We can use this component in our Index component:

```ruby
# app/hyperstack/components/index.rb
class Index < HyperComponent
  render(SECTION) do
    UL do
      Todo.each do |todo|
        TodoItem(todo: todo)
      end
    end
  end
end
```

Now you will see something like

Header will go here  Footer will go here &lt;/div&gt;   


As you can see components can take parameters \(or props in react.js terminology.\)

> _Rails uses the terminology params \(short for parameters\) which have a similar purpose to React props, so to make the transition more natural for Rails programmers Hyperstack uses params, rather than props._

Params are declared using the `param` macro which creates an _accessor_ method of the same name within the component.

Our `Index` component _mounts_ a new `TodoItem` with each `Todo` record and passes the `Todo` to the `TodoItem` component as the parameter.

Now go back to Rails console and type

```ruby
Todo.last.update(title: 'updated todo')
```

and you will see the last Todo in the list changing.

Try adding another Todo using `create` like you did before. You will see the new Todo is added to the list.

## Chapter 5: Adding Inputs to Components

So far we have seen how our components are synchronized to the data that they display. Next let's add the ability for the component to _change_ the underlying data.

First add an `INPUT` html tag to your TodoItem component like this:

```ruby
# app/hyperstack/components/todo_item.rb
class TodoItem < HyperComponent
  param :todo
  render(LI) do
    INPUT(type: :checkbox, checked: todo.completed)
    todo.title
  end
end
```

You will notice that while it does display the checkboxes, you can not change them by clicking on them.

For now we can change them via the console like we did before. Try executing

```ruby
Todo.last.update(completed: true)
```

and you should see the last Todo's `completed` checkbox changing state.

To make our checkbox input change its own state, we will add an `event handler` for the change event:

```ruby
# app/hyperstack/components/todo_item.rb
class TodoItem < HyperComponent
  param :todo
  render(LI) do
    INPUT(type: :checkbox, checked: todo.completed)
    .on(:change) { todo.update(completed: !todo.completed) }
    todo.title
  end
end
```

It reads like a good novel doesn't it? On the `change` event update the todo, setting the completed attribute to the opposite of its current value. The rest of coordination between the database and the display is taken care of for you by the Hyperstack.

After saving your changes you should be able change the `completed` state of each Todo, and check on the rails console \(say by checking `Todo.last.completed`\) and you will see that the value has been persisted to the database. You can also demonstrate this by refreshing the page.

We will finish up by adding a _delete_ link at the end of the Todo item:

```ruby
# app/hyperstack/components/todo_item.rb
class TodoItem < HyperComponent
  param :todo
  render(LI) do
    INPUT(type: :checkbox, checked: todo.completed)
    .on(:change) { todo.update(completed: !todo.completed) }
    SPAN { todo.title } # See note below...
    A { ' -X-' }.on(:click) { todo.destroy }
  end
end
```

**Note:** _If a component or tag block returns a string it is automatically wrapped in a SPAN, to insert a string in the middle you have to wrap it a SPAN like we did above._

I hope you are starting to see a pattern here. Hyperstack components determine what to display based on the `state` of some objects. External events, such as mouse clicks, the arrival of new data from the server, and even timers update the `state`. Hyperstack recomputes whatever portion of the display depends on the `state` so that the display is always in sync with the `state`. In our case the objects are the Todo model and its associated records, which have a number of associated internal `states`.

By the way, you don't have to use Models to have states. We will see later that states can be as simple as boolean instance variables.

## Chapter 6: Routing

Now that Todos can be _completed_ or _active_, we would like our user to be able display either "all" Todos, only "completed" Todos, or "active" \(or incomplete\) Todos. We want our URL to reflect which filter is currently being displayed. So `/all` will display all todos, `/completed` will display the completed Todos, and of course `/active` will display only active \(or incomplete\) Todos. We would also like the root url `/` to be treated as `/all`

To achieve this we first need to be able to _scope_ \(or filter\) the Todo Model. So let's edit the Todo model file so it looks like this:

```ruby
# app/hyperstack/models/todo.rb
class Todo < ApplicationRecord
  scope :completed, -> { where(completed: true)  }
  scope :active,    -> { where(completed: false) }
end
```

Now we can say `Todo.all`, `Todo.completed`, and `Todo.active`, and get the desired subset of Todos. You might want to try it now in the rails console.  
**Note:** _you will have to do a `reload!` to load the changes to the Model._

We would like the URL of our App to reflect which of these _filters_ is being displayed. So if we load

* `/all` we want the Todo.all scope to be run;
* `/completed` we want the Todo.completed scope to be run;
* `/active` we want the Todo.active scope to be run;
* `/` \(by itself\) then we should redirect to `/all`.

Having the application display different data \(or whole different components\) based on the URL is called routing.

Lets change `App` to look like this:

```ruby
# app/hyperstack/components/app.rb
class App < HyperComponent
  include Hyperstack::Router
  render(SECTION) do
    Header()
    Route('/', exact: true) { Redirect('/all') }
    Route('/:scope', mounts: Index)
    Footer()
  end
end
```

and the `Index` component to look like this:

```ruby
# app/hyperstack/components/index.rb
class Index < HyperComponent
  include Hyperstack::Router::Helpers
  render(SECTION) do
    UL do
      Todo.send(match.params[:scope]).each do |todo|
        TodoItem(todo: todo)
      end
    end
  end
end
```

Lets walk through the changes:

* We mount the `Header` components as before.
* We then check to see if the current route exactly matches `/` and if it does, redirect to `/all`.
* Then instead of directly mounting the `Index` component, we _route_ to it based on the URL.  In this case if the url must look like `/xxx`.
* `Index` now includes \(mixes-in\) the `Hyperstack::Router::Helpers` module which has methods like `match`.
* Instead of simply enumerating all the Todos, we decide which _scope_ to filter using the URL fragment _matched_ by `:scope`.  

Notice the relationship between `Route('/:scope', mounts: Index)` and `match.params[:scope]`:

During routing each `Route` is checked. If it _matches_ then the indicated component is mounted, and the match parameters are saved for that component to use.

You should now be able to change the url from `/all`, to `/completed`, to `/active`, and see a different set of Todos. For example if you are displaying the `/active` Todos, you will only see the Todos that are not complete. If you check one of these it will disappear from the list.

> Rails also has the concept of routing, so how do the Rails and Hyperstack routers interact? Have a look at the config/routes.rb file. You will see a line like this: `get '/(*other)', to: 'hyperstack#app'` This is telling Rails to accept all requests and to process them using the `Hyperstack` controller, which will attempt to mount a component named `App` in response to the request. The mounted App component is then responsible for further processing the URL.
>
> For more complex scenarios Hyperstack provides Rails helper methods that can be used to mount components from your controllers, layouts, and views.

## Chapter 7:  Helper Methods, Inline Styling, Active Support and Router Nav Links

Of course we will want to add navigation to move between these routes. We will put the navigation in the footer:

```ruby
# app/hyperstack/components/footer.rb
class Footer < HyperComponent
  def link_item(path)
    A(href: "/#{path}", style: { marginRight: 10 }) { path.camelize }
  end
  render(DIV) do
    link_item(:all)
    link_item(:active)
    link_item(:completed)
  end
end
```

Save the file, and you will now have 3 links, that you will change the path between the three options.

Here is how the changes work:

* Hyperstack is just Ruby, so you are free to use all of Ruby's rich feature set to structure your code.

  For example the `link_item` method is just a _helper_ method to save us some typing.

* The `link_item` method uses the `path` argument to construct an HTML _Anchor_ tag.
* Hyperstack comes with a large portion of the Rails active-support library.

  For the text of the anchor tag we use the active-support method `camelize`.

* Later we will add proper css classes, but for now we use an inline style.

  Notice that the css `margin-right` is written `marginRight`, and that `10px` can be expressed as the integer 10.

Notice that as you click each link the page reloads. **However** what we really want is for the links to simply change the route, without reloading the page.

To make this happen we will _mixin_ some router helpers by _including_ `HyperRouter::ComponentMethods` inside of class.

Then we can replace the anchor tag with the Router's `NavLink` component:

Change

```ruby
A(href: "/#{path}", style: { marginRight: 10 }) { path.camelize }
```

to

```ruby
NavLink("/#{path}", style: { marginRight: 10 }) { path.camelize }
# note that there is no href key in NavLink
```

Our component should now look like this:

```ruby
# app/hyperstack/components/footer.rb
class Footer < HyperComponent
  include Hyperstack::Router::Helpers
  def link_item(path)
    NavLink("/#{path}", style: { marginRight: 10 }) { path.camelize }
  end
  render(DIV) do
    link_item(:all)
    link_item(:active)
    link_item(:completed)
  end
end
```

After this change you will notice that changing routes _does not_ reload the page, and after clicking to different routes, you can use the browsers forward and back buttons.

How does it work? The `NavLink` component reacts to a click just like an anchor tag, but instead of changing the window's URL directly, it updates the _HTML5 history object._ Associated with this history is \(hope you guessed it\) _state_. So when the history changes it causes any components depending on the state of the URL to be re-rendered.

## Chapter 8: Create a Basic EditItem Component

So far we can mark Todos as completed, delete them, and filter them. Now we create an `EditItem` component so we can change the Todo title.

Add a new component like this:

```ruby
# app/hyperstack/components/edit_item.rb
class EditItem < HyperComponent
  param :todo
  render do
    INPUT(defaultValue: todo.title)
    .on(:enter) do |evt|
      todo.update(title: evt.target.value)
    end
  end
end
```

Before we use this component let's understand how it works.

* It receives a `todo` param which will be edited by the user;
* The `title` of the todo is displayed as the initial value of the input;
* When the user types the enter key the `todo` is updated.

Now update the `TodoItem` component replacing

```ruby
SPAN { todo.title }
```

with

```ruby
EditItem(todo: todo)
```

Try it out by changing the text of some our your Todos followed by the enter key. Then refresh the page to see that the Todos have changed.

## Chapter 9: Adding State to a Component, Defining Custom Events, and a Lifecycle Callback.

This all works, but it's hard to use. There is no feedback indicating that a Todo has been saved, and there is no way to cancel after starting to edit. We can make the user interface much nicer by adding _state_ \(there is that word again\) to the `TodoItem`. We will call our state `editing`. If `editing` is true, then we will display the title in a `EditItem` component, otherwise we will display it in a `LABEL` tag. The user will change the state to `editing` by double clicking on the label. When the user saves the Todo, we will change the state of `editing` back to false. Finally we will let the user _cancel_ the edit by moving the focus away \(the `blur` event\) from the `EditItem`. To summarize:

* User double clicks on any Todo title: editing changes to `true`.
* User saves the Todo being edited: editing changes to `false`.
* User changes focus away \(`blur`\) from the Todo being edited: editing changes to `false`.

In order to accomplish this our `EditItem` component is going to communicate to its parent via two application defined events - `saved` and `cancel`.

Add the following 5 lines to the `EditItem` component like this:

```ruby
# app/hyperstack/components/edit_item.rb
class EditItem < HyperComponent
  param :todo
  fires :saved                               # add
  fires :cancel                              # add
  after_mount { jQ[dom_node].focus }         # add

  render do
    INPUT(defaultValue: todo.title)
    .on(:enter) do |evt|
      todo.update(title: evt.target.value)
      saved!                                 # add
    end
    .on(:blur) { cancel! }                   # add
  end
end
```

The first two new lines add our custom events which will be _fired_ by the component.

The next new line uses one of several _Lifecycle Callbacks_. In this case we need to move the focus to the `EditItem` component after it is mounted. The `jQ` method is Hyperstack's jQuery wrapper, and `dom_node` is the method that returns the actual dom node where this _instance_ of the component is mounted. This is the `INPUT` html element as defined in the render method.

The `saved!` line will fire the saved event in the parent component. Notice that the method to fire a custom event is the name of the event followed by a bang \(!\).

Finally we add the `blur` event handler and fire our `cancel` event.

Now we can update our `TodoItem` component to react to three events: `double_click`, `saved` and `cancel`.

```ruby
# app/hyperstack/components/todo_item.rb
class TodoItem < HyperComponent
  param :todo
  render(LI) do
    if @editing
      EditItem(todo: todo)
      .on(:saved, :cancel) { mutate @editing = false }
    else
      INPUT(type: :checkbox, checked: todo.completed)
      .on(:change) { todo.update(completed: !todo.completed) }
      LABEL { todo.title }
      .on(:double_click) { mutate @editing = true }
      A { ' -X-' }
      .on(:click) { todo.destroy }
    end
  end
end
```

All states in Hyperstack are simply Ruby instance variables \(ivars for short which are variables with a leading @\). Here we use the `@editing` ivar.

We have already used a lot of states that are built into the HyperModel and HyperRouter. The states of these components are built out of collections of instance variables like `@editing`.

In the `TodoItem` component the value of `@editing` controls whether to render the `EditItem` or the INPUT, LABEL, and Anchor tags.

Because `@editing` \(like all ivars\) starts off as nil, when the `TodoItem` first mounts, it renders the INPUT, LABEL, and Anchor tags. Attached to the label tag is a `double_click` handler which does one thing: _mutates_ the component's state setting `@editing` to true. This then causes the component to re-render, and now instead of the three tags, we will render the `EditItem` component.

Attached to the `EditItem` component is the `saved` and `cancel` handler \(which is shared between the two events\) that _mutates_ the component's state, setting `@editing` back to false.

Using and changing state in a component is as simple as reading or changing the value of some instance variables. The only caveat is that whenever you want to change a state variable whether it's a simple assignment or changing the internal value of a complex structure like a hash or array you use the `mutate` method to signal Hyperstack that that state is changing.

## Chapter 10: Using EditItem to create new Todos

Our `EditItem` component has a good robust interface. It takes a Todo, and lets the user edit the title, and then either save or cancel, using two custom events to communicate back outwards.

Because of this we can easily reuse `EditItem` to create new Todos. Not only does this save us time, but it also insures that the user interface acts consistently.

Update the `Header` component to use `EditItem` like this:

```ruby
# app/hyperstack/components/header.
class Header < HyperComponent
  before_mount { @new_todo = Todo.new }
  render(HEADER) do
    EditItem(todo: @new_todo)
    .on(:saved) { mutate @new_todo = Todo.new }
  end
end
```

What we have done is initialize an instance variable `@new_todo` to a new unsaved `Todo` item in the `before_mount` lifecycle method.

Then we pass the value `@new_todo` to EditItem, and when it is saved, we generate another new Todo and save it in the `new_todo` state variable.

When `Header`'s state is mutated, it will cause a re-render of the Header, which will then pass the new value of `@new_todo`, to `EditItem`, causing that component to also re-render.

We don't care if the user cancels the edit, so we simply don't provide a `:cancel` event handler.

Once the code is added a new input box will appear at the top of the window, and when you type enter a new Todo will be added to the list.

However you will notice that the value of new Todo input box does not clear. This is subtle problem but it's easy to fix.

React treats the `INPUT` tag's `defaultValue` specially. It is only read when the `INPUT` is first mounted, so it _does not react_ to changes like normal parameters. Our `Header` component does pass in new Todo records, but even though they are changing React _does not_ update the INPUT.

React has a special param called `key`. React uses this to uniquely identify mounted components. It's used to keep track of lists of components, in this case it can also be used to indicate that the component needs to be remounted when the value of `key` is changed.

All objects in Hyperstack respond to the `to_key` method which will return a suitable unique key id, so all we have to do is pass `todo` as the key param, this will insure that as `todo` changes, we will re-initialize the `INPUT` tag.

```ruby
...
INPUT(defaultValue: todo.title, key: todo) # add the special key param
...
```

## Chapter 11: Adding Styling

We are just going to steal the style sheet from the benchmark Todo app, and add it to our assets.

**Go grab the file in this repo here:** [https://github.com/hyperstack-org/hyperstack/blob/edge/docs/tutorial/assets/todo.css](https://github.com/hyperstack-org/hyperstack/blob/edge/docs/tutorial/assets/todo.css) and copy it to a new file called `todo.css` in the `app/assets/stylesheets/` directory.

You will have to refresh the page after changing the style sheet.

Now its a matter of updating the css classes which are passed to components via the `class` parameter.

Let's start with the `App` component. With styling it will look like this:

```ruby
# app/hyperstack/components/app.rb
class App < HyperComponent
  include Hyperstack::Router
  render(SECTION, class: 'todo-app') do # add class todo-app
    Header()
    Route('/', exact: true) { Redirect('/all') }
    Route('/:scope', mounts: Index)
    Footer()
  end
end
```

The `Footer` component needs to have a `UL` added to hold the links nicely, and we can also use the `NavLinks` `active_class` param to highlight the link that is currently active:

```ruby
# app/hyperstack/components/footer.rb
class Footer < HyperComponent
  include Hyperstack::Router::Helpers
  def link_item(path)
    # wrap the NavLink in a LI and
    # tell the NavLink to change the class to :selected when
    # the current (active) path equals the NavLink's path.
    LI { NavLink("/#{path}", active_class: :selected) { path.camelize } }
  end
  render(DIV, class: :footer) do   # add class footer
    UL(class: :filters) do         # wrap links in a UL element with class filters
      link_item(:all)
      link_item(:active)
      link_item(:completed)
    end
  end
end
```

For the Index component just add the `main` and `todo-list` classes.

```ruby
# app/hyperstack/components/index.rb
class Index < HyperComponent
  include Hyperstack::Router::Helpers
  render(SECTION, class: :main) do         # add class main
    UL(class: 'todo-list') do              # add class todo-list
      Todo.send(match.params[:scope]).each do |todo|
        TodoItem(todo: todo)
      end
    end
  end
end
```

For the EditItem component we want the parent to pass any html parameters such as `class` along to the INPUT tag. We do this by adding the special `other` param that will collect any extra params, we then pass it along in to the INPUT tag. Hyperstack will take care of merging all the params together sensibly.

```ruby
# app/hyperstack/components/edit_item.rb
class EditItem < HyperComponent
  param :todo
  fires :saved
  fires :cancel
  other :etc  # can be named anything you want
  after_mount { jQ[dom_node].focus }
  render do
    INPUT(etc, defaultValue: todo.title, key: todo)
    .on(:enter) do |evt|
      todo.update(title: evt.target.value)
      saved!
    end
    .on(:blur) { cancel! }
  end
end
```

Now we can add classes to the TodoItem's list-item, input, anchor tags, and to the `EditItem` component:

```ruby
# app/hyperstack/components/todo_item.rb
class TodoItem < HyperComponent
  param :todo
  render(LI, class: 'todo-item') do # add the todo-item class
    if @editing
      EditItem(class: :edit, todo: todo)  # add the edit class
      .on(:saved, :cancel) { mutate @editing = false }
    else
      INPUT(type: :checkbox, class: :toggle, checked: todo.completed) # add the toggle class
      .on(:change) { todo.update(completed: !todo.completed) }
      LABEL { todo.title }
      .on(:double_click) { mutate @editing = true }
      A(class: :destroy) # add the destroy class and remove the -X- placeholder
      .on(:click) { todo.destroy }
    end
  end
end
```

In the Header we can send a different class to the `EditItem` component. While we are at it we will add the `H1 { 'todos' }` hero unit.

```ruby
# app/hyperstack/components/header.
class Header < HyperComponent
  before_mount { @new_todo = Todo.new }
  render(HEADER, class: :header) do                   # add the 'header' class
    H1 { 'todos' }                                    # add the hero unit.
    EditItem(class: 'new-todo', todo: @new_todo)      # add 'new-todo' class
    .on(:saved) { mutate @new_todo = Todo.new }
  end
end
```

At this point your Todo App should be properly styled.

## Chapter 12: Other Features

* **Show How Many Items Left In Footer**  

  This is just a span that we add before the link tags list in the `Footer` component:

```ruby
...
render(DIV, class: :footer) do
  SPAN(class: 'todo-count') do
    # pluralize returns the second param (item) properly
    # pluralized depending on the first param's value.
    "#{pluralize(Todo.active.count, 'item')} left"
  end
  UL(class: :filters) do
...
```

* **Add 'placeholder' Text To Edit Item**  

  `EditItem` should display a meaningful placeholder hint if the title is blank:

```ruby
...
INPUT(etc, placeholder: 'What is left to do today?',
            defaultValue: todo.title, key: todo)
.on(:enter) do |evt|
...
```

* **Don't Show the Footer If There are No Todos**  

  In the `App` component add a _guard_ so that we won't show the Footer if there are no Todos:

```ruby
...
Footer() unless Todo.count.zero?
...
```

Congratulations! you have completed the tutorial.

## Summary

You have built a small but feature rich full stack Todo application in less than 100 lines of code:

```text
SLOC  
--------------
App:         9
Header:      8
Index:      10
TodoItem:   16
EditItem:   16
Footer:     16
Todo Model:  4
Rails Route: 4
--------------
Total:      83
```

The complete application is shown here:

```ruby
# app/hyperstack/components/app.rb
class App < HyperComponent
  include Hyperstack::Router
  render(SECTION, class: 'todo-app') do
    Header()
    Route('/', exact: true) { Redirect('/all') }
    Route('/:scope', mounts: Index)
    Footer() unless Todo.count.zero?
  end
end

# app/hyperstack/components/header.
class Header < HyperComponent
  before_mount { @new_todo = Todo.new }
  render(HEADER, class: :header) do
    H1 { 'todos' }
    EditItem(class: 'new-todo', todo: @new_todo)
    .on(:saved) { mutate @new_todo = Todo.new }
  end
end

# app/hyperstack/components/index.rb
class Index < HyperComponent
  include Hyperstack::Router::Helpers
  render(SECTION, class: :main) do
    UL(class: 'todo-list') do
      Todo.send(match.params[:scope]).each do |todo|
        TodoItem(todo: todo)
      end
    end
  end
end

# app/hyperstack/components/footer.rb
class Footer < HyperComponent
  include Hyperstack::Router::Helpers
  def link_item(path)
    LI { NavLink("/#{path}", active_class: :selected) { path.camelize } }
  end
  render(DIV, class: :footer) do
    SPAN(class: 'todo-count') { "#{pluralize(Todo.active.count, 'item')} left" }
    UL(class: :filters) do
      link_item(:all)
      link_item(:active)
      link_item(:completed)
    end
  end
end

# app/hyperstack/components/todo_item.rb
class TodoItem < HyperComponent
  param :todo
  render(LI, class: 'todo-item') do
    if @editing
      EditItem(class: :edit, todo: todo)
      .on(:saved, :cancel) { mutate @editing = false }
    else
      INPUT(type: :checkbox, class: :toggle, checked: todo.completed)
      .on(:change) { todo.update(completed: !todo.completed) }
      LABEL { todo.title }
      .on(:double_click) { mutate @editing = true }
      A(class: :destroy)
      .on(:click) { todo.destroy }
    end
  end
end

# app/hyperstack/components/edit_item.rb
class EditItem < HyperComponent
  param :todo
  fires :save
  fires :cancel
  other :etc
  after_mount { jQ[dom_node].focus }
  render do
    INPUT(etc, placeholder: 'What is left to do today?',
                defaultValue: todo.title, key: todo)
    .on(:enter) do |evt|
      todo.update(title: evt.target.value)
      saved!
    end
    .on(:blur) { cancel! }
  end
end

# app/hyperstack/models/todo.rb
class Todo < ApplicationRecord
  scope :completed, -> { where(completed: true)  }
  scope :active,    -> { where(completed: false) }
end

# config/routes.rb
Rails.application.routes.draw do
  mount Hyperstack::Engine => '/hyperstack'
  get '/(*other)', to: 'hyperstack#app'
end
```

## General troubleshooting

1: Wait. On initial boot it can take several minutes to pre-compile all the system assets.

2: Make sure to save \(or better yet do a git commit\) after every instruction so that you can backtrack.

3: Its possible to get things so messed up the hot-reloader will not work. Restart the server and reload the browser.

4: Reach out to us on Slack, we are always happy to help get you onboarded!
