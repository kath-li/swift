// RUN: %target-swift-frontend -emit-sil %s -verify

func trapsAndOverflows() {
  // The error message below is generated by the traditional constant folder.
  // expected-error @+1 {{arithmetic operation '124 + 92' (on type 'Int8') results in an overflow}}
  #assert((124 as Int8) + 92 < 42)

  // expected-error @+2 {{integer literal '123231' overflows when stored into 'Int8'}}
  // expected-error @+1 {{#assert condition not constant}}
  #assert(Int8(123231) > 42)
  // expected-note @-1 {{integer overflow detected}}

  // expected-error @+2 {{arithmetic operation '124 + 8' (on type 'Int8') results in an overflow}}
  // expected-error @+1 {{assertion failed}}
  #assert(Int8(124) + 8 > 42)

  // expected-error @+1 {{#assert condition not constant}}
  #assert({ () -> Int in fatalError(String()) }() > 42)
  // expected-note @-1 {{trap detected}}

  // expected-error @+1 {{#assert condition not constant}}
  #assert({ () -> Int in fatalError("") }() > 42)
  // expected-note @-1 {{trap detected}}
}

func isOne(_ x: Int) -> Bool {
  return x == 1
}

func assertionSuccess() {
  #assert(isOne(1))
  #assert(isOne(1), "1 is not 1")
}

func assertionFailure() {
  #assert(isOne(2)) // expected-error{{assertion failed}}
  #assert(isOne(2), "2 is not 1") // expected-error{{2 is not 1}}
}

func nonConstant() {
  #assert(isOne(Int(readLine()!)!)) // expected-error{{#assert condition not constant}}
  #assert(isOne(Int(readLine()!)!), "input is not 1") // expected-error{{#assert condition not constant}}
}

func recursive(a: Int) -> Int {
  if a == 0 { return 0 }     // expected-note {{expression is too large to evaluate at compile-time}}
  return recursive(a: a-1)
}

func test_recursive() {
  // expected-error @+1 {{#assert condition not constant}}
  #assert(recursive(a: 20000) > 42)
}

// @constexpr
func loops1(a: Int) -> Int {
  var x = 42
  while x <= 42 {
    x += a
  } // expected-note {{control flow loop found}}
  return x
}


// @constexpr
func loops2(a: Int) -> Int {
  var x = 42
  // expected-note @+1 {{expression not evaluable as constant here}}
  for i in 0 ... a {
    x += i
  }
  return x
}


func test_loops() {
  // expected-error @+1 {{#assert condition not constant}}
  #assert(loops1(a: 20000) > 42)

  // expected-error @+1 {{#assert condition not constant}}
  #assert(loops2(a: 20000) > 42)
}

//===----------------------------------------------------------------------===//
// Reduced testcase propagating substitutions around.
protocol SubstitutionsP {
  init<T: SubstitutionsP>(something: T)

  func get() -> Int
}

struct SubstitutionsX : SubstitutionsP {
  var state : Int
  init<T: SubstitutionsP>(something: T) {
    state = something.get()
  }
  func get() -> Int {
    fatalError()
  }

  func getState() -> Int {
    return state
  }
}

struct SubstitutionsY : SubstitutionsP {
  init() {}
  init<T: SubstitutionsP>(something: T) {
  }

  func get() -> Int {
    return 123
  }
}
func substitutionsF<T: SubstitutionsP>(_: T.Type) -> T {
  return T(something: SubstitutionsY())
}

func testProto() {
  #assert(substitutionsF(SubstitutionsX.self).getState() == 123)
}

//===----------------------------------------------------------------------===//
// Generic thunk - partial_apply testcase.
//===----------------------------------------------------------------------===//

struct Transform<T> {
  let fn: (T) -> T
}
func double(x: Int) -> Int {
  return x + x
}

func testGenericThunk() {
  let myTransform = Transform(fn: double)

  // This is because we don't support partial application yet.
  // TODO: expected-error @+1 {{#assert condition not constant}}
  #assert(myTransform.fn(42) > 1)
  // expected-note @-1{{could not fold operation}}
}

//===----------------------------------------------------------------------===//
// Enums and optionals.
//===----------------------------------------------------------------------===//

func isNil(_ x: Int?) -> Bool {
  return x == nil
}

#assert(isNil(nil))
#assert(!isNil(3))

public enum Pet {
  case bird
  case cat(Int)
  case dog(Int, Int)
  case fish
}

public func weighPet(pet: Pet) -> Int {
  switch pet {
  case .bird: return 3
  case let .cat(weight): return weight
  case let .dog(w1, w2): return w1+w2
  default: return 1
  }
}

#assert(weighPet(pet: .bird) == 3)
#assert(weighPet(pet: .fish) == 1)
#assert(weighPet(pet: .cat(2)) == 2)
// expected-error @+1 {{assertion failed}}
#assert(weighPet(pet: .cat(2)) == 3)

#assert(weighPet(pet: .dog(9, 10)) == 19)

func foo() -> Bool {
  // expected-note @+1 {{could not fold operation}}
  print("not constexpr")
  return true
}

func baz() -> Bool {
  return foo() // expected-note {{when called from here}}
}

func bar() -> Bool {
  return baz() // expected-note {{when called from here}}
}

func testCallStack() {
  #assert(bar()) // expected-error{{#assert condition not constant}}
}

//===----------------------------------------------------------------------===//
