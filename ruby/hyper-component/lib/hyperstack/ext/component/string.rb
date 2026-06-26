class String
  # For String, to_key can just be the string itself (like Number#to_key).
  # Don't rely on Object#to_key -> object_id: Opal <= 1.6 returned the string
  # primitive from String#object_id, but Opal 1.8 returns an integer id, which
  # broke `"x".to_key == "x"`.
  def to_key
    self
  end

  def event_camelize
    `return #{self}.replace(/(^|_)([^_]+)/g, function(match, pre, word, index) {
      var capitalize = true;
      return capitalize ? word.substr(0,1).toUpperCase()+word.substr(1) : word;
    })`
  end
end
