
## # Z3
##
## This library provides a Nim binding to the Z3 theorem prover.
##
## ## Z3 context
##
## Almost all Z3 C API functions take a Z3_context argument. This Nim binding
## uses a block level template called `z3` which creates a Z3_context and injects
## this into the template scope. All other Z3 functions are implemented using
## templates who use this implicitly available context variable.
##
## ## Z3 AST types
##
## The Z3 C API uses one single type `Z3_ast` for all possible node sorts.
## Internally, the `Z3_ast` has a type (called "sorts") which can be boolean,
## integer, real, etc.  Z3 provides a lot of functions for building AST trees,
## but it requires the programmer to keep track of the implicit type to make
## sure the right functions are called for the right nodes.  For example, to add
## two numbers of the sort `Z3_INT_KIND`, the `Z3_mk_add` function is used, but
## to add to numbers of the sort `Z3_BV_SORT` the user needs to call
## `Z3_mk_bvadd`.
##
## This Nim binding allows the usage of native operators, so the user can simply
## use the `+` operator instead of `Z3_mk_add`. For this reason, Nim needs to keep 
## track of the underlying Z3 node sort for each Z3 ast node. Other API's like the 
## Python binding do this by wrapping each `Z3_ast` node in an external object, and
## provide methods applying to these objects. This Nim binding uses distinct
## types instead: for each Z3 node sort, there is a matching Nim type provided of
## the type `distinct Z3_ast`.
##
## * `Z3_ast_bool`: A node of the kind `Z3_BOOL_SORT`. To create a Z3 AST node
##                  of this type use the `Bool()` template
##
## * `Z3_ast_bv`: A node of the kind `Z3_BV_SORT`. To create a Z3 AST node of
##                this type use the `Bv(length)` template, where the `length`
##                argument indicates the bitvector size
##
## * `Z3_ast_int`: A node of the kind `Z3_INT_SORT`. To create a Z3 AST node
##                 of this type use the `Int()` template
##
## * `Z3_ast_fpa`: A node of the kind `Z3_FLOATING_POINT_SORT`. To create a Z3
##                 AST node of this type use the `Float()` template. At this
##                 time floating point nodes are all of the `double` sort.
##
## ## Operators
##
## All Nim operators working on Z3 AST nodes are defined for the appropriate
## Z3_ast types only, and make sure they return the proper type as well. This
## allows the programmer to freely mix and match Z3 operators, and the Nim
## compiler will make sure all types are validated at compile time, instead of
## relying on run-time exceptions generated by the Z3 library. For example:
##
## .. code-block::nim
##   z3:
##     let s = Solver()
##
##     let i1 = Int("i1")
##     let i2 = Int("i2")
##     let b = Bool("b")
##     let f1 = Float("f1")
##
##     s.assert b == (i1 * i2 == 25) and (i1 + i2) == 10
##     s.assert b and (f1 == 3.0)
##
##     s.check_model:
##       echo model
##
## More examples are available in the nimble tests at https://github.com/zevv/nimz3/blob/master/tests/test1.nim
##
## For more info on Z3 check the official guide at https://rise4fun.com/z3/tutorialcontent/guide

import z3/z3_api
from strutils import parseFloat
from math import pow

export Z3_ast

type

  Z3Exception* = object of Exception
    ## Exception thrown from the Z3 error handler. The exception message is
    ## generated by the Z3 library and states the reason for the error

  Z3_ast_ptr = ptr Z3_ast

  Z3_ast_bool* = distinct Z3_ast
  Z3_ast_bv* = distinct Z3_ast
  Z3_ast_int* = distinct Z3_ast
  Z3_ast_fpa* = distinct Z3_ast

  Z3_ast_any = Z3_ast | Z3_ast_bool | Z3_ast_bv | Z3_ast_int | Z3_ast_fpa


# Z3 type constructors

template mk_var(name: string, ty: Z3_sort): Z3_ast =
  let sym = Z3_mk_string_symbol(ctx, name)
  Z3_mk_const(ctx, sym, ty)

template Bool*(name: string): Z3_ast_bool =
  ## Create a Z3 constant of the type Bool.
  mk_var(name, Z3_mk_bool_sort(ctx)).Z3_ast_bool

template Int*(name: string): Z3_ast_int =
  ## Create a Z3 constant of the type Int.
  mk_var(name, Z3_mk_int_sort(ctx)).Z3_ast_int

template Bv*(name: string, sz: int): Z3_ast_bv =
  ## Create a Z3 constant of the type BV with a size of `sz` bits.
  mk_var(name, Z3_mk_bv_sort(ctx, sz.cuint)).Z3_ast_bv

template Float*(name: string): Z3_ast_fpa =
  ## Create a Z3 constant of the type Float.
  mkvar(name, Z3_mk_fpa_sort_double(ctx)).Z3_ast_fpa



# Stringifications

template `$`*(v: Z3_ast_any): string =
  ## Create a string representation of the Z3 ast node
  {.push hint[ConvFromXtoItselfNotNeeded]: off.}
  $Z3_ast_to_string(ctx, v.Z3_ast)

template `$`*(m: Z3_model): string =
  ## Create a string representation of the Z3 model
  $Z3_model_to_string(ctx, m)

template `$`*(m: Z3_solver): string =
  ## Create a string representation of the Z3 solver
  $Z3_solver_to_string(ctx, m)

template `$`*(m: Z3_optimize): string =
  ## Create a string representation of the Z3 optimizer
  $Z3_optimize_to_string(ctx, m)

template `$`*(m: Z3_pattern): string =
  ## Create a string representation of the Z3 pattern
  $Z3_pattern_to_string(ctx, m)



# Misc

template simplify*(s: Z3_ast_any): Z3_ast =
  Z3_simplify(ctx, s.Z3_ast)


#
# Solver interface
#

template Solver*(): Z3_solver =
  ## Create a Z3 solver context
  Z3_mk_solver(ctx)

template assert*(s: Z3_solver, e: Z3_ast_any) =
  ## Assert hard constraint to the solver context.
  Z3_solver_assert(ctx, s, e.Z3_ast)

template check*(s: Z3_solver): Z3_lbool =
  ## Check whether the assertions in a given solver are consistent or not.
  Z3_solver_check(ctx, s)

template get_model*(s: Z3_Solver): Z3_model =
  ## Retrieve the model for the last solver.check
  Z3_solver_get_model(ctx, s)

template push*(s: Z3_Solver, code: untyped) =
  ## Create a backtracking point. This is to be used as a block scope template,
  ## so the state pop will by automatically generated when leaving the scope:
  ##
  ## .. code-block::nim
  ##   z3:
  ##     let s = Solver()
  ##     s.assert ...
  ##     s.push:
  ##       s.assert ..
  ##       s.check
  ##     s.assert ...
  ##
  Z3_solver_push(ctx, s)
  block:
    code
  Z3_solver_pop(ctx, s, 1)

template check_model*(s: Z3_solver, code: untyped) =
  ## A helper block-scope template that combines `check` and `get_model`. If
  ## the solver was consistent the model is available in the variable `model`
  ## inside the block scope. If the solver failed a Z3Exception will be thrown.
  if Z3_solver_check(ctx, s) == Z3_L_TRUE:
    let model {.inject.} = Z3_solver_get_model(ctx, s)
    code
  else:
    raise newException(Z3Exception, "UNSAT")


#
# Optimizer interface
#

template Optimizer*(): Z3_optimize =
  ## Create a Z3 optimizer
  Z3_mk_optimize(ctx)

template minimize*(o: Z3_optimize, e: Z3_ast_any) =
  ## Add a minimization constraint.
  echo Z3_optimize_minimize(ctx, o, e.Z3_ast)

template maximize*(o: Z3_optimize, e: Z3_ast_any) =
  ## Add a maximization constraint.
  echo Z3_optimize_maximize(ctx, o, e.Z3_ast)

template assert*(o: Z3_optimize, e: Z3_ast_any) =
  ## Assert hard constraint to the optimization context.
  Z3_optimize_assert(ctx, o, e.Z3_ast)

template check*(s: Z3_optimize): Z3_lbool =
  ## Check whether the assertions in a given optimize are consistent or not.
  Z3_optimize_check(ctx, s)

template get_model*(s: Z3_optimize): Z3_model =
  ## Retrieve the model for the last optimize.check
  Z3_optimize_get_model(ctx, s)

template check_model*(s: Z3_optimize, code: untyped) =
  if Z3_optimize_check(ctx, s) == Z3_L_TRUE:
    let model {.inject.} = Z3_optimize_get_model(ctx, s)
    code
  else:
    raise newException(Z3Exception, "UNSAT")

#
# Misc
#

template eval*(v: Z3_ast_any): Z3_ast =
  var r: Z3_ast
  if not Z3_model_eval(ctx, model, v.Z3_ast, true, addr r):
    raise newException(Z3Exception, "eval failed")
  r

template evalInt*(v: Z3_ast_any): int =
  var c: cint
  if not Z3_get_numeral_int(ctx, eval(v), addr c):
    raise newException(Z3Exception, "evalInt: can not convert")
  c

template evalFloat*(v: Z3_ast_any): float =
  let ss = splitWhitespace $Z3_get_numeral_string(ctx, eval(v))
  ss[0].parseFloat * pow(2.0, ss[1].parseFloat)

proc on_err(ctx: Z3_context, e: Z3_error_code) {.nimcall.} =
  let msg = $Z3_get_error_msg_ex(ctx, e)
  raise newException(Z3Exception, msg)


template z3*(code: untyped) =

  ## The main Z3 context template. This template creates an implicit
  ## Z3_context which all other API functions need. Z3 errors are
  ## caught and throw a Z3Exception

  block:

    let cfg = Z3_mk_config()
    Z3_set_param_value(cfg, "model", "true");
    let ctx {.inject used.} = Z3_mk_context(cfg)
    let fpa_rm {.inject used.} = Z3_mk_fpa_round_nearest_ties_to_even(ctx)
    Z3_del_config(cfg)
    Z3_set_error_handler(ctx, on_err)

    block:
      code



#
# Operators working on Z3_ast nodes
#

# Helpers to create a Nim value to the appropriate Z3_ast sort

proc to_Z3_ast(ctx: Z3_context, v: Z3_ast_any): Z3_ast =
  v.Z3_ast

proc to_Z3_ast(ctx: Z3_context, v: bool, sort: Z3_sort = nil): Z3_ast =
  if v: Z3_mk_true(ctx) else: Z3_mk_false(ctx)

proc to_Z3_ast(ctx: Z3_context, v: SomeInteger, sort: Z3_sort = nil): Z3_ast =
  Z3_mk_int64(ctx, v.clonglong, sort)

proc to_Z3_ast(ctx: Z3_context, v: float, sort: Z3_sort = nil): Z3_ast =
  Z3_mk_fpa_numeral_double(ctx, v.cdouble, sort)

proc to_Z3_ast(ctx: Z3_context, v: string, sort: Z3_sort = nil): Z3_ast =
  Z3_mk_numeral(ctx, v, sort)


# Generator helpers: these allow calling of binop type functions (like
# Z3_mk_xor) or vararg-type functions (like Z3_mk_add) through the same
# signature.

template helper_bin(ctx: Z3_context, fn: untyped, v1, v2: Z3_ast_any): Z3_ast =
  fn(ctx, v1.Z3_ast, v2.Z3_ast)

template helper_var(ctx: Z3_context, fn: untyped, v1, v2: Z3_ast_any): Z3_ast =
  let vs = [v1.Z3_ast, v2.Z3_ast]
  fn(ctx, 2, unsafeAddr vs[0])

template helper_bin_fpa(ctx: Z3_context, fn: untyped, v1, v2: Z3_ast_any): Z3_ast =
  fn(ctx, fpa_rm, v1.Z3_ast, v2.Z3_ast)

template helper_uni(ctx: Z3_context, fn: untyped, v: Z3_ast): Z3_ast =
  fn(ctx, v)

template helper_uni_fpa(ctx: Z3_context, fn: untyped, v: Z3_ast_any): Z3_ast =
  fn(ctx, fpa_rm, v.Z3_ast)


# Generator templates for an unary operators

template uniop(name: untyped, Tin, Tout: untyped, fn: untyped, helper: untyped) =

  template name*(a: Tin): Tout =
    helper(ctx, fn, a.Z3_ast).Tout


# Generator templates for an binary operators

template binop(name: untyped, Tin, Tout: untyped, fn: untyped, helper: untyped) =

  template name*(a1, a2: Tin): Tout =
    helper(ctx, fn, a1, a2).Tout

  template name*[T](a1: Tin, a2: T): Tout =
    helper(ctx, fn, a1, to_Z3_ast(ctx, a2, Z3_get_sort(ctx, a1.Z3_ast)).Tin).Tout

  template name*[T](a1: T, a2: Tin): Tout =
    helper(ctx, fn, to_Z3_ast(ctx, a1, Z3_get_sort(ctx, a2.Z3_ast)).Tin, a2).Tout


# Boolean operators and functions

binop(`and`, Z3_ast_bool, Z3_ast_bool, Z3_mk_and, helper_var)
binop(`or`, Z3_ast_bool, Z3_ast_bool, Z3_mk_or, helper_var)
binop(`xor`, Z3_ast_bool, Z3_ast_bool, Z3_mk_xor, helper_bin)
binop(`==`, Z3_ast_bool, Z3_ast_bool, Z3_mk_eq, helper_bin)
binop(`<->`, Z3_ast_bool, Z3_ast_bool, Z3_mk_iff, helper_bin)
uniop(`not`, Z3_ast_bool, Z3_ast_bool, Z3_mk_not, helper_uni)

# Bit vector operators and functions

binop(`and`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvand, helper_bin)
binop(`mod`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvsmod, helper_bin)
binop(`nor`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvnor, helper_bin)
binop(`or`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvor , helper_bin)
binop(`shl`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvshl, helper_bin)
binop(`shr`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvlshr, helper_bin)
binop(`xnor`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvxnor, helper_bin)
binop(`xor`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvxor, helper_bin)
binop(`>=`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvsge, helper_bin)
binop(`>`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvsgt, helper_bin)
binop(`<=`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvsle, helper_bin)
binop(`<`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvslt, helper_bin)
binop(`%>=`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvuge, helper_bin)
binop(`%>`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvugt, helper_bin)
binop(`%<=`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvule, helper_bin)
binop(`%<`, Z3_ast_bv, Z3_ast_bool, Z3_mk_bvult, helper_bin)
binop(`==`, Z3_ast_bv, Z3_ast_bool, Z3_mk_eq, helper_bin)
binop(`<->`, Z3_ast_bv, Z3_ast_bool, Z3_mk_iff, helper_bin)
binop(`+`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvadd, helper_bin)
binop(`*`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvmul, helper_bin)
binop(`/`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvsdiv, helper_bin)
binop(`-`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvsub, helper_bin)
binop(`/%`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvudiv, helper_bin)
binop(`&`, Z3_ast_bv, Z3_ast_bv, Z3_mk_concat, helper_bin)
uniop(`not`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvnot, helper_uni)
uniop(`-`, Z3_ast_bv, Z3_ast_bv, Z3_mk_bvneg, helper_uni)

# Integer operators and functions

binop(`==`, Z3_ast_int, Z3_ast_bool, Z3_mk_eq, helper_bin)
binop(`>=`, Z3_ast_int, Z3_ast_bool, Z3_mk_ge, helper_bin)
binop(`>`, Z3_ast_int, Z3_ast_bool, Z3_mk_gt, helper_bin)
binop(`<->`, Z3_ast_int, Z3_ast_bool, Z3_mk_iff, helper_bin)
binop(`<=`, Z3_ast_int, Z3_ast_bool, Z3_mk_le, helper_bin)
binop(`<`, Z3_ast_int, Z3_ast_bool, Z3_mk_lt, helper_bin)
binop(`+`, Z3_ast_int, Z3_ast_int, Z3_mk_add, helper_var)
binop(`/`, Z3_ast_int, Z3_ast_int, Z3_mk_div, helper_bin)
binop(`*`, Z3_ast_int, Z3_ast_int, Z3_mk_mul, helper_var)
binop(`-`, Z3_ast_int, Z3_ast_int, Z3_mk_sub, helper_var)
uniop(`-`, Z3_ast_int, Z3_ast_int, Z3_mk_unary_minus, helper_uni)

# Floating point operators and functions

binop(`==`, Z3_ast_fpa, Z3_ast_bool, Z3_mk_eq, helper_bin)
binop(`>=`, Z3_ast_fpa, Z3_ast_bool, Z3_mk_fpa_ge, helper_bin)
binop(`>`, Z3_ast_fpa, Z3_ast_bool, Z3_mk_fpa_gt, helper_bin)
binop(`<->`, Z3_ast_fpa, Z3_ast_bool, Z3_mk_fpa_iff, helper_bin)
binop(`<=`, Z3_ast_fpa, Z3_ast_bool, Z3_mk_fpa_le, helper_bin)
binop(`<`, Z3_ast_fpa, Z3_ast_bool, Z3_mk_fpa_lt, helper_bin)
binop(`<->`, Z3_ast_fpa, Z3_ast_bool, Z3_mk_iff, helper_bin)
binop(`+`, Z3_ast_fpa, Z3_ast_fpa, Z3_mk_fpa_add, helper_bin_fpa)
binop(`/`, Z3_ast_fpa, Z3_ast_fpa, Z3_mk_fpa_div, helper_bin_fpa)
binop(`*`, Z3_ast_fpa, Z3_ast_fpa, Z3_mk_fpa_mul, helper_bin_fpa)
binop(`-`, Z3_ast_fpa, Z3_ast_fpa, Z3_mk_fpa_sub, helper_bin_fpa)
uniop(abs, Z3_ast_fpa, Z3_ast_fpa, Z3_mk_fpa_abs, helper_uni)
uniop(sqrt, Z3_ast_fpa, Z3_ast_fpa, Z3_mk_fpa_sqrt, helper_uni_fpa)
uniop(`-`, Z3_ast_fpa, Z3_ast_fpa, Z3_mk_fpa_neg, helper_uni)

# Miscellaneous

proc vararg_helper[T](ctx: Z3_context, fn: T, vs: varargs[Z3_ast_any]): Z3_ast =
  fn(ctx, vs.len.cuint, Z3_ast_ptr(unsafeAddr(vs[0])))

template distinc*[T: Z3_ast_bool|Z3_ast_bv|Z3_ast_int](vs: varargs[T]): Z3_ast_bool =
  vararg_helper(ctx, Z3_mk_distinct, vs).Z3_ast_bool

template ite*[T](v1: bool|Z3_ast_bool, v2, v3: T): T =
  T(Z3_mk_ite(ctx, to_Z3_ast(ctx, v1), to_Z3_ast(ctx, v2), to_Z3_ast(ctx, v3)))

template exists*(vs: openarray[Z3_ast_any], body: Z3_ast_bool): Z3_ast_bool =
  var bound: seq[Z3_app]
  for v in vs: bound.add Z3_to_app(ctx, v.Z3_ast)
  Z3_mk_exists_const(ctx, 0, bound.len.cuint, addr(bound[0]), 0, nil, body.Z3_ast).Z3_ast_bool

template ∃*(vs: openarray[Z3_ast_any], body: Z3_ast_bool): Z3_ast_bool =
  exists(vs, body)

template forall*(vs: openarray[Z3_ast_any], body: Z3_ast_bool): Z3_ast_bool =
  var bound: seq[Z3_app]
  for v in vs: bound.add Z3_to_app(ctx, v.Z3_ast)
  Z3_mk_forall_const(ctx, 0, bound.len.cuint, addr(bound[0]), 0, nil, body.Z3_ast).Z3_ast_bool

template ∀*(vs: openarray[Z3_ast_any], body: Z3_ast_bool): Z3_ast_bool =
  forall(vs, body)

# vim: ft=nim

