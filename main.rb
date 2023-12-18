class EmptyStackError < StandardError
end

class INotInLoopError < StandardError
end

class UninitializedHeapAccess < StandardError
end

$stack = []

$in_string = false
$in_comment = false
$in_func_def = false
$in_if = false
$in_else = false
$in_while_loop_content = false
$in_for_loop_content = false
$for_loop_running = false

$func_def = [] # pair [func_name, func_definition]
$if_flags = [] # stack of true/false indicating flag of most recently evaluated if statement. uses a stack for the sake of nested if statements
$loop_contents = []

$loop_begin = -1
$loop_end = -1
$loop_i = -1

$error_thrown = false

$next_addr = 1000
$variables = {} # hash 'var_name' => 'heap_addr'
$heap = {} # hash 'heap_addr' => 'value'
$constants = {} # hash 'const_name' => 'value'
$next_is_var_name = false
$next_is_const_name = false
$next_const_val = -1

$cell_width = 1

# symmetric operators eg. addition just pop 2 and operate
# nonsymmetric operators eg. subtraction pop and store before operating to ensure the correct order
$dictionary = {
  '+' => -> { word_wrapper('+') { pop + pop } },
  '-' => -> { word_wrapper('-') { n2, n1 = pop, pop; n1 - n2} },
  '*' => -> { word_wrapper('*') { pop * pop; } },
  '/' => -> { word_wrapper('/') { n2, n1 = pop, pop; n1 / n2} },
  'mod' => -> { word_wrapper('mod') { n2, n1 = pop, pop; n1 % n2 } },
  'dup' => -> { word_wrapper('dup') { if $stack.last then $stack.last else raise EmptyStackError end } },
  'swap' => -> { word_wrapper('swap') { [pop].push(pop) } },
  'drop' => -> { word_wrapper('drop') { pop; nil } },
  'dump' => -> { print($stack, "\n"); nil }, # don't use puts because it removes square braces
  'over' => -> { word_wrapper('over') { n2, n1 = pop, pop; [n1, n2, n1] } },
  'rot' => -> { word_wrapper('rot') { n3, n2, n1 = pop, pop, pop; [n2, n3, n1] } },
  '.' => -> { word_wrapper('.') { print(Integer(pop), ' '); nil} },
  'emit' => -> { word_wrapper('emit') { print pop.chr; nil } },
  'cr' => -> { puts },
  '=' => -> { word_wrapper('=') { if pop == pop then -1 else 0 end} },
  '<' => -> { word_wrapper('<') { n2, n1 = pop, pop; if n1 < n2 then -1 else 0 end } },
  '>' => -> { word_wrapper('>') { n2, n1 = pop, pop; if n1 > n2 then -1 else 0 end } },
  'and' => -> { word_wrapper('and') { pop & pop } },
  'or' => -> { word_wrapper('or') { pop | pop } },
  'xor' => -> { word_wrapper('xor') { pop ^ pop } },
  'invert' => -> { word_wrapper('invert') { ~pop } },
  '."' => -> { $in_string = true; nil },
  '(' => -> { $in_comment = true; nil },
  ':' => -> { $in_func_def = true; $func_def = ['', '']; nil },
  'if' => -> { word_wrapper('if') { $if_flags.push(pop != 0); $in_if = true; $in_else = false; nil } },
  'begin' => -> { $in_while_loop_content = true; nil },
  'do' => -> { word_wrapper('do') { $in_for_loop_content = true; $loop_begin = pop; $loop_end = pop; nil } },
  'i' => -> { word_wrapper('i') { if $for_loop_running then $loop_i else raise INotInLoopError end } },
  'variable' => -> { $next_is_var_name = true; nil },
  '!' => -> { word_wrapper('!') { var = pop; value = pop; $heap[var] = value; nil } },
  '@' => -> { word_wrapper('@') { var = pop; if $heap[var] then $heap[var] else raise UninitializedHeapAccess end } },
  'constant' => -> { word_wrapper('constant') { $next_is_const_name = true; $next_const_val = pop; nil } },
  'allot' => -> { word_wrapper('allot') { $next_addr += pop; nil } },
  'cells' => -> { word_wrapper('cells') { pop * $cell_width } },

  # below cases are handled in the eval function when successful so if they get evaluated from the dictionary, there was an error
  'loop' => -> { puts 'error: tried to use "loop" outside of DO ... LOOP'; $error_thrown = true; nil },
  ';' => -> { puts 'error: tried to use ";" outside of : ... ;'; $error_thrown = true; nil },
  ')' => -> { puts 'error: tried to use ")" outside of ( ... )'; $error_thrown = true; nil },
  '"' => -> { puts 'error: tried to use " outside of ." ... "'; $error_thrown = true; nil },
  'until' => -> { puts 'error: tried to use "until" outside of BEGIN ... UNTIL'; $error_thrown = true; nil },
  #'else' => -> { puts 'error: tried to use "else" outside of IF ... ELSE ... THEN'; $error_thrown = true; nil },
  #'then' => -> { puts 'error: tried to use "then" outside of IF ... ELSE ... THEN'; $error_thrown = true; nil },
}

# wrapper for words that that catches errors
def word_wrapper(key)
  $error_thrown = true
  
  begin
    ret = yield
  rescue EmptyStackError
    # reset flags when certain words fail
    if key == 'if'
      $in_if = false
      $in_else = false
    elsif key == 'do'
      $in_for_loop_content = false
      $loop_end = -1
      $loop_begin = -1
    end
    
    puts 'error: not enough items in stack to call "' + key + '"'
  rescue INotInLoopError
    puts 'error: tried to access "i" while not in a DO ... LOOP construct'
  rescue ZeroDivisionError
    puts 'error: division by zero in "' + key + '"'
  rescue UninitializedHeapAccess
    puts 'error: tried to access uninitialized heap memory'
  else
    # this gets executed when no error is thrown
    $error_thrown = false
    return ret
  end
end

# custom pop function to raise an error on empty stack
def pop
  p = $stack.pop
  if p
    p
  else
    raise EmptyStackError
  end
end

def eval(symbol)
  #print symbol, ' ', $if_flags, ' '
  skip = false
  
  # skip all evals once an error has been thrown
  if $error_thrown 
    return
  end

  if $next_is_var_name
    $variables[symbol] = $next_addr

    $next_addr += 1
    $next_is_var_name = false
    skip = true
  end

  if $next_is_const_name
    $constants[symbol] = $next_const_val

    $next_is_const_name = false
    skip = true
  end
  
  if $in_for_loop_content
    if symbol.downcase == 'loop'
      $in_for_loop_content = false

      $for_loop_running = true
      for i in $loop_begin...$loop_end
        $loop_i = i
        $loop_contents.each {|i| eval i; nil}
      end
      $for_loop_running = false
      $loop_contents = []
    else
      $loop_contents.push symbol
    end
  
    skip = true
  end

  if $in_while_loop_content
    if symbol.downcase == 'until'
      $in_while_loop_content = false
      
      loop do
        $loop_contents.each {|i| eval i; nil}
        if $stack.last != 0
          break
        end
      end
      
      $stack.pop
      $loop_contents = []
    else
      $loop_contents.push symbol
    end
    
    skip = true
  end
  
  # if statement handling
  if symbol.downcase == 'else'
    $in_if = false
    $in_else = true
    skip = true
  elsif symbol.downcase == 'then'
    $in_else = false
    $if_flags.pop # reached end of if statement, so pop it from flag stack
    skip = true
  end

  if $in_if && !$if_flags.last
    skip = true
  elsif $in_else && $if_flags.last
    skip = true
  end
  
  # function definition handling
  if $in_func_def
    if symbol.include? ';'
      $in_func_def = false

      # create a deep copy of func_def to prevent issues with creating multiple functions
      func_def_copy = Marshal.load( Marshal.dump($func_def) )
      
      $dictionary[func_def_copy[0]] = -> { func_def_copy[1].split.each {|i| eval i}; nil }
    end

    if $func_def[0] == ''
      $func_def[0] = symbol
    else
      $func_def[1] += (symbol + ' ')
    end

    skip = true
  end

  # comment handling
  if $in_comment
    if symbol.include? ')'
      $in_comment = false
    end

    skip = true
  end

  # string handling
  if $in_string
    # end create_string when encountering " in symbol
    if symbol.include? '"'
      $in_string = false
      print(symbol.delete('"')) # remove " character and don't print space if this is the end of string
    else
      print(symbol, ' ')
    end
    
    skip = true
  end

  if skip 
    return
  end

  if $variables.has_key? symbol
    $stack.push($variables[symbol])
    return
  end

  if $constants.has_key? symbol
    $stack.push($constants[symbol])
    return
  end
  
  if $dictionary.has_key? symbol.downcase
    $stack.push($dictionary[symbol.downcase].call)
    
    # flatten handles push cases where dictionary call returns an array eg. SWAP
    $stack.flatten!
    # compact removes cases that return nil eg. DROP
    $stack.compact!
  else
    # convert numbers to integer before pushing to stack
    begin
      $stack.push Integer(symbol)
    rescue
      puts 'error: unknown symbol "' + symbol + '"'
      $error_thrown = true
    end
  end

end

# repl
while true do
  print"\t"
  gets.split.each {|i| eval i}

  if !$error_thrown && !$in_string && !$in_comment && !$in_func_def && !$in_for_loop_content && !$in_while_loop_content
    print " ok\n"
  end
  $error_thrown = false
end
