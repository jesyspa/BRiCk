(*
 * Copyright (c) 2020-2022 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)
(**
 * Semantics of expressions
 * (expressed in weakest pre-condition style)
 *)
Require Export bedrock.prelude.numbers.
Require Import iris.proofmode.tactics.

From bedrock.lang.cpp Require Import ast semantics.
From bedrock.lang.cpp.logic Require Import
     pred path_pred heap_pred
     operator
     destroy
     initializers
     wp call string
     translation_unit
     dispatch layout.
Require Import bedrock.lang.bi.errors.

Require Import bedrock.lang.cpp.heap_notations.

Module Type Expr.
  (* Needed for [Unfold wp_test] *)
  #[local] Arguments wp_test [_ _ _] _ _ _.
  #[local] Open Scope free_scope.

  (**
   * Weakest pre-condition for expressions

     NOTE It is important that these rules are sound, but less important that
     they are complete. When in doubt, we err on the side of caution and under-specify
     the behavior of various constructs.

     If you run into code that requires addditional semantic specification, please file
     an issue.

     NOTE Since [wp_operand] can be used to prove [wp_init] but not vice-versa, we
          use [wp_operand] to specify the semantics of any expression that is guaranteed
          to return a primitive.
   *)

  Section with_resolve.
    Context `{Σ : cpp_logic thread_info} {resolve:genv}.
    Variables (tu : translation_unit) (ρ : region).

    #[local] Notation wp_lval := (wp_lval tu ρ).
    #[local] Notation wp_prval := (wp_prval tu ρ).
    #[local] Notation wp_xval := (wp_xval tu ρ).
    #[local] Notation wp_init := (wp_init tu ρ).
    #[local] Notation wp_operand := (wp_operand tu ρ).
    #[local] Notation wp_initialize := (wp_initialize tu ρ).
    #[local] Notation wp_test := (wp_test tu ρ).
    #[local] Notation wp_discard := (wp_discard tu ρ).
    #[local] Notation wp_glval := (wp_glval tu ρ).
    #[local] Notation wp_args := (wp_args tu ρ).
    #[local] Notation interp := (interp tu).
    (* TODO Fix these *)
    #[local] Notation fspec := (fspec resolve.(genv_tu).(globals)).
    #[local] Notation mspec := (mspec resolve.(genv_tu).(globals)).

    #[local] Notation glob_def := (glob_def resolve) (only parsing).
    #[local] Notation size_of := (@size_of resolve) (only parsing).

    (** * References

        References are allocated explicitly in our semantics and are read
        using a special [Eread_ref] node that is inserted into the program.

        NOTE this rule requires that both [int&& x] and [int& x] are materialized
        into [Tref].
     *)
    Axiom wp_lval_read_ref : forall e Q,
        wp_lval e (fun r free => Exists (p : ptr),
           (Exists q, r |-> primR (Tref $ erase_qualifiers $ type_of e) q (Vptr p) ** True) //\\ Q p free)
      |-- wp_lval (Eread_ref e) Q.

    (* constants are rvalues *)
    Axiom wp_operand_constant : forall ty cnst e Q,
      tu.(globals) !! cnst = Some (Gconstant ty (Some e)) ->
          (* evaluation of the expression does not get access to
             local variables, so it gets [Remp] rather than [ρ].
             In addition, the evaluation is done at compile-time, so we clean
             up the temporaries eagerly. *)
          WPE.wp_operand tu (Remp None None ty) e (fun v frees => interp frees $ Q v FreeTemps.id)
      |-- wp_operand (Econst_ref (Gname cnst) ty) Q.

    (* integer literals are prvalues *)
    Axiom wp_operand_int : forall n ty Q,
      [! has_type (Vint n) (drop_qualifiers ty) !] //\\ Q (Vint n) FreeTemps.id
      |-- wp_operand (Eint n ty) Q.

    (* note that `char` is actually `byte` *)
    Axiom wp_operand_char : forall c ty Q,
      [! has_type (Vint c) (drop_qualifiers ty) !] //\\ Q (Vint c) FreeTemps.id
      |-- wp_operand (Echar c ty) Q.

    (* boolean literals are prvalues *)
    Axiom wp_operand_bool : forall (b : bool) Q,
      Q (Vbool b) FreeTemps.id
      |-- wp_operand (Ebool b) Q.

    (** * String Literals

        The standard states <https://eel.is/c++draft/lex.string#9>:

            | Evaluating a string-literal results in a string literal object with
            | static storage duration ([basic.stc]). Whether all string-literals
            | are distinct (that is, are stored in nonoverlapping objects) and whether
            | successive evaluations of a string-literal yield the same or a different
            | object is unspecified.
            |
            | [Note 4: The effect of attempting to modify a string literal object is
            | undefined. — end note]

        which means the C++ abstract machine manages ownership of string literals
        during its lifetime, handing out read-access to the underlying memory when
        necessary - in an implementation-defined way.

        We treat this in our logic by granting a pair of resources
        each time a string literal is evaluated:

        1. a read-only (fraction < 1) of memory containing the string, and
        2. a destroyer which can be used to give the values back to
           the abstract machine.

        Note that the pointer `p` is universally quantified. This follows
        the standard which does *not* guarantee that successive evaluations
        of the same string literal will return the same pointer
        (in practice, this generally only occurs when there are multiple
         translation units involved).

        Note that the fancy update is necessary to support a model where
        the string pool is maintained within an invariant of the abstract
        machine.
     *)
    Axiom wp_lval_string : forall bytes ty Q,
          match drop_qualifiers ty with
          | Tarray ty' _ =>
            Forall (p : ptr) (q : Qp),
              (p |-> cstring.R q bytes **
               (p |-> cstring.R q bytes ={⊤}=∗ emp)) -*
              Q p FreeTemps.id
          | _ => False
          end
      |-- wp_lval (Estring bytes ty) Q.

    (* `this` is a prvalue *)
    Axiom wp_operand_this : forall ty Q,
          valid_ptr (_this ρ) ** Q (Vptr $ _this ρ) FreeTemps.id
      |-- wp_operand (Ethis ty) Q.

    (* variables are lvalues *)
    Axiom wp_lval_lvar : forall ty x Q,
          valid_ptr (_local ρ x) ** Q (_local ρ x) FreeTemps.id
      |-- wp_lval (Evar (Lname x) ty) Q.

    (* what about the type? if it exists *)
    Axiom wp_lval_gvar : forall ty x Q,
          valid_ptr (_global x) ** Q (_global x) FreeTemps.id
      |-- wp_lval (Evar (Gname x) ty) Q.

    (* [Emember a f ty] is an lvalue by default except when
     * - where [m] is a member enumerator or a non-static member function, or
     * - where [a] is an rvalue and [m] is a non-static data member of non-reference type
     *
     * NOTE We need [vc] in order to distinguish the two forms of [rvalue], [xvalue] and [prvalue]
     *)
    Axiom wp_lval_member : forall ty vc a m Q,
        match vc with
        | Prvalue => False
        | Lvalue =>
          wp_lval a (fun base free =>
                       let addr := base ,, _field m in
                       valid_ptr addr ** Q addr free)
        | Xvalue => False
          (* NOTE If the object is a temporary, then the field access will also be a
             temporary. Being conservative is sensible in our semantic style.
          *)
        end
      |-- wp_lval (Emember vc a m ty) Q.

    (* [Emember a m ty] is an xvalue if
     * - [a] is an rvalue and [m] is a non-static data member of non-reference type
     *)
    Axiom wp_xval_member : forall ty vc a m Q,
        match vc with
        | Prvalue => False
          (* This does not occur because our AST explicitly contains [Cl2r] casts.
           *)
        | Xvalue =>
          wp_xval a (fun base free =>
                       let addr := base ,, _field m in
                       valid_ptr addr ** Q addr free)
        | _ => False
        end%I
      |-- wp_xval (Emember vc a m ty) Q.

    Fixpoint is_pointer (ty : type) : bool :=
      match ty with
      | Tpointer _
      | Tarray _ _ => true
      | Tqualified _ t => is_pointer t
      | _ => false
      end.

    (* [Esubscript a n ty] is an lvalue if
     * - one operand is an lvalue array
     *   (in clang's syntax tree, this value is converted to an rvalue via
     *    an array2pointer cast)
     *)
    Axiom wp_lval_subscript : forall e i t Q,
      nd_seq (wp_operand e) (wp_operand i) (fun '(ev, iv) free =>
         let '(base, idx) :=
           if is_pointer (type_of e) then (ev,iv) else (iv,ev)
         in
         Exists i, [| idx = Vint i |] **
         let addr := _eqv base .[ erase_qualifiers t ! i ] in
         valid_ptr addr ** Q addr free)
      |-- wp_lval (Esubscript e i t) Q.

    (* [Esubscript e i t]
     * - where one operand is an array rvalue
     *)
    Axiom wp_xval_subscript : forall e i t Q,
      nd_seq (wp_operand e) (wp_operand i) (fun '(ev, iv) free =>
         let '(base, idx) :=
           if is_pointer (type_of e) then (ev,iv) else (iv,ev)
         in
          (* TODO: here and elsewhere, consider avoiding locations and switching to *)
          (* (Exists i basep, [| idx = Vint i /\ base = Vptr basep |] **
            ((valid_ptr (basep .,, o_sub resolve (erase_qualifiers t) i) ** True) //\\
            Q (Vptr (basep .,, o_sub resolve (erase_qualifiers t) i)) (free' ** free)))) *)
          (Exists i, [| idx = Vint i |] **
           let addr := _eqv base .[ erase_qualifiers t ! i ] in
           valid_ptr addr ** Q addr free))
      |-- wp_xval (Esubscript e i t) Q.

    (** * Unary Operators
     *)

    (** the `*` operator is an lvalue

        > The unary * operator performs indirection: the expression to which it is applied
        > shall be a pointer to an object type, or a pointer to a function type and the
        > result is an lvalue referring to the object or function to which the expression
        > points. If the type of the expression is “pointer to T”, the type of the result
        > is “T”.

        https://eel.is/c++draft/expr.unary.op#1
     *)
    Axiom wp_lval_deref : forall ty e Q,
        wp_operand e (fun v free =>
                      match v with
                      | Vptr p => Q p free
                      | _ => False
                      end)
        |-- wp_lval (Ederef e ty) Q.

    (** the `&` operator

        https://eel.is/c++draft/expr.unary.op#3
     *)
    Axiom wp_operand_addrof : forall e Q,
        wp_lval e (fun p free => Q (Vptr p) free)
        |-- wp_operand (Eaddrof e) Q.

    (** "pure" unary operators on primmitives, e.g. `-`, `!`, etc.

        NOTE this rule assumes that [eval_unop] is deterministic.
     *)
    Axiom wp_operand_unop : forall o e ty Q,
        wp_operand e (fun v free => (* todo: rval? *)
          Exists v',
          [| eval_unop tu o (drop_qualifiers (type_of e)) (drop_qualifiers ty) v v' |] **
          Q v' free)
        |-- wp_operand (Eunop o e ty) Q.

    (** `++e`
        https://eel.is/c++draft/expr.pre.incr#1
     *)
    Axiom wp_lval_preinc : forall e ty Q,
        (let ety := type_of e in
         let eety := erase_qualifiers ety in
         match companion_type eety with
         | Some cty =>
          wp_lval e (fun a free => Exists v' v'',
              (eval_binop tu Badd eety cty (erase_qualifiers ty) v' (Vint 1) v'' ** True) //\\
              (a |-> primR eety 1 v' **
                (a |-> primR eety 1 v'' -* Q a free)))
         | None => False
         end)
        |-- wp_lval (Epreinc e ty) Q.

    (** `--e`
        https://eel.is/c++draft/expr.pre.incr#2
     *)
    Axiom wp_lval_predec : forall e ty Q,
        (let ety := type_of e in
         let eety := erase_qualifiers ety in
         match companion_type eety with
         | Some cty =>
          wp_lval e (fun a free => Exists v' v'',
              (eval_binop tu Bsub eety cty (erase_qualifiers ty) v' (Vint 1) v'' ** True) //\\
              (a |-> primR eety 1 v' **
                (a |-> primR eety 1 v'' -* Q a free)))
         | None => False
         end)
        |-- wp_lval (Epredec e ty) Q.

    (** `e++`
        https://eel.is/c++draft/expr.post.incr#1
     *)
    Axiom wp_operand_postinc : forall e ty Q,
        (let ety := type_of e in
         let eety := erase_qualifiers ety in
         match companion_type eety with
         | Some cty =>
             wp_lval e (fun a free => Exists v', Exists v'',
                          (eval_binop tu Badd eety cty
                             (erase_qualifiers ty) v' (Vint 1) v'' ** True) //\\
                            (a |-> primR eety 1 v' **
                               (a |-> primR eety 1 v'' -* Q v' free)))
         | None => False
         end)
      |-- wp_operand (Epostinc e ty) Q.

    (** `e--`
        https://eel.is/c++draft/expr.post.incr#2
     *)
    Axiom wp_operand_postdec : forall e ty Q,
        (let ety := type_of e in
         let eety := erase_qualifiers ety in
         match companion_type eety with
         | Some cty =>
             wp_lval e (fun a free => Exists v', Exists v'',
                          (eval_binop tu Bsub eety cty
                             (erase_qualifiers ty) v' (Vint 1) v'' ** True) //\\
                            (a |-> primR eety 1 v' **
                               (a |-> primR eety 1 v'' -* Q v' free)))
         | None => False
         end)
     |-- wp_operand (Epostdec e ty) Q.

    (** * Binary Operators *)
    (* NOTE the following axioms assume that [eval_binop] is deterministic *)
    Axiom wp_operand_binop : forall o e1 e2 ty Q,
        nd_seq (wp_operand e1) (wp_operand e2) (fun '(v1,v2) free =>
          Exists v',
            (eval_binop tu o
                (drop_qualifiers (type_of e1)) (drop_qualifiers (type_of e2))
                (drop_qualifiers ty) v1 v2 v' ** True) //\\
            Q v' free)
        |-- wp_operand (Ebinop o e1 e2 ty) Q.

    (* NOTE the right operand is sequenced before the left operand in C++20,
       check when this started. (cppreference.com doesn't seem to have this information)
     *)
    Axiom wp_lval_assign : forall ty l r Q,
        nd_seq (wp_lval l) (wp_operand r) (fun '(la, rv) free =>
            la |-> anyR (erase_qualifiers ty) 1 **
           (la |-> primR (erase_qualifiers ty) 1 rv -* Q la free))
        |-- wp_lval (Eassign l r ty) Q.

    (* Assignemnt operators are *almost* like regular assignments except that they
       guarantee to evaluate the left hand side *exactly* once (rather than twice
       which is what would come from the standard desugaring)
     *)
    Axiom wp_lval_bop_assign : forall ty o l r Q,
        nd_seq (wp_lval l) (wp_operand r) (fun '(la, rv) free =>
             (Exists v v', la |-> primR (erase_qualifiers ty) 1 v **
                 ((eval_binop tu o (erase_qualifiers (type_of l)) (erase_qualifiers (type_of r)) (erase_qualifiers (type_of l)) v rv v' ** True) //\\
                 (la |-> primR (erase_qualifiers ty) 1 v' -* Q la free))))
        |-- wp_lval (Eassign_op o l r ty) Q.

    (** The comma operator can be both an lvalue and a prvalue
        depending on what the second expression is.

        `a, b` runs `a`, discards the value (but does not clean it up yet),
        then runs `b`. the value (and temporaries) of `a` are destroyed
        after `b` completes (usually at the end of the statement).
     *)
    Axiom wp_lval_comma : forall {vc} e1 e2 Q,
        wp_discard vc e1 (fun free1 => wp_lval e2 (fun val free2 => Q val (free2 >*> free1)))
        |-- wp_lval (Ecomma vc e1 e2) Q.

    Axiom wp_xval_comma : forall {vc} e1 e2 Q,
        wp_discard vc e1 (fun free1 => wp_xval e2 (fun val free2 => Q val (free2 >*> free1)))
        |-- wp_xval (Ecomma vc e1 e2) Q.

    Axiom wp_operand_comma : forall {vc} e1 e2 Q,
        wp_discard vc e1 (fun free1 => wp_operand e2 (fun val free2 => Q val (free2 >*> free1)))
        |-- wp_operand (Ecomma vc e1 e2) Q.

    Axiom wp_init_comma : forall {vc} ty p e1 e2 Q,
        wp_discard vc e1 (fun free1 => wp_init ty p e2 (fun fval free2 => Q fval (free2 >*> free1)))
        |-- wp_init ty p (Ecomma vc e1 e2) Q.

    (** short-circuting operators *)
    Axiom wp_operand_seqand : forall e1 e2 Q,
        Unfold WPE.wp_test (wp_test e1 (fun c free1 =>
        (* ^ note: technically an rvalue, but it must be a primitive,
           otherwise there will be an implicit cast to bool, to it is
           always an rvalue *)
           if c
           then wp_test e2 (fun c free2 => (* see comment above *)
                              Q (Vbool c) (free2 >*> free1))
           else Q (Vbool c) free1))
        |-- wp_operand (Eseqand e1 e2) Q.

    Axiom wp_operand_seqor : forall e1 e2 Q,
        Unfold WPE.wp_test (wp_test e1 (fun c free1 =>
        (* ^ note: technically an rvalue, but it must be a primitive,
           otherwise there will be an implicit cast to bool, to it is
           always an rvalue *)
           if c
           then Q (Vbool c) free1
           else wp_test e2 (fun c free2 => (* see comment above *)
                              Q (Vbool c) (free2 >*> free1))))
        |-- wp_operand (Eseqor e1 e2) Q.

    (** * Casts
        Casts apply exclusively to primitive types, all other casts in C++
        are represented as overloaded functions.
     *)

    (** [Cl2r] represents reads of locations. *)
    Axiom wp_operand_cast_l2r_l : forall ty e Q,
        wp_lval e (fun a free => Exists v,
           (Exists q, a |-> primR (erase_qualifiers ty) q v ** True) //\\ Q v free)
        |-- wp_operand (Ecast Cl2r Lvalue e ty) Q.

    Axiom wp_operand_cast_l2r_x : forall ty e Q,
        wp_xval e (fun a free => Exists v, (* was wp_lval *)
          (Exists q, a |-> primR (erase_qualifiers ty) q v ** True) //\\ Q v free)
        |-- wp_operand (Ecast Cl2r Xvalue e ty) Q.

    (** [Cnoop] casts are no-op casts. *)
    Axiom wp_init_cast_noop : forall ty ty' e p Q,
        wp_init ty p e Q
        |-- wp_init ty p (Ecast Cnoop Prvalue e ty') Q.
    Axiom wp_operand_cast_noop : forall ty e Q,
        wp_operand e Q
        |-- wp_operand (Ecast Cnoop Prvalue e ty) Q.

    Axiom wp_lval_cast_noop : forall ty e Q,
        wp_lval e Q
        |-- wp_lval (Ecast Cnoop Lvalue e ty) Q.
    Axiom wp_xval_cast_noop : forall ty e Q,
        wp_xval e Q
        |-- wp_xval (Ecast Cnoop Xvalue e ty) Q.

    (* note: this is the cast that occurs for the implementation of
     * [std::move]
     *)
    Axiom wp_lval_xval_cast_noop : forall ty e Q,
        wp_xval e Q
        |-- wp_lval (Ecast Cnoop Xvalue e ty) Q.
    Axiom wp_xval_lval_cast_noop : forall ty e Q,
        wp_lval e Q
        |-- wp_xval (Ecast Cnoop Lvalue e ty) Q.

    Definition int2bool_not_num (v : val) : Set.
    Proof. exact unit. Qed.

    Axiom wp_operand_cast_int2bool : forall ty e Q,
        wp_operand e (fun v free =>
                        match v with
                        | Vint n => Q (Vbool (bool_decide (n <> 0))) free
                        | _ => ERROR (int2bool_not_num v)
                        end)
        |-- wp_operand (Ecast Cint2bool Prvalue e ty) Q.

    Definition ptr2bool_not_ptr (v : val) : Set.
    Proof. exact unit. Qed.

    Axiom wp_operand_cast_ptr2bool : forall ty e Q,
        wp_operand e (fun v free =>
                      match v with
                      | Vptr p => Q (Vbool (bool_decide (p <> nullptr))) free
                      | _ => ERROR (ptr2bool_not_ptr v)
                      end)
        |-- wp_operand (Ecast Cptr2bool Prvalue e ty) Q.

    (** [Cfun2ptr] is a cast from a function to a pointer.

       note that C and C++ classify function names differently, so we
       end up with two cases
       - in C, function names are Rvalues, and
       - in C++, function names are Lvalues
     *)
    Axiom wp_operand_cast_fun2ptr_c : forall ty ty' g Q,
        wp_lval (Evar (Gname g) ty') (fun v => Q (Vptr v))
            (* even though they are [prvalues], we reuse the [Lvalue] rule for
               evaluating them. *)
        |-- wp_operand (Ecast Cfun2ptr Prvalue (Evar (Gname g) ty') ty) Q.
    Axiom wp_operand_cast_fun2ptr_cpp : forall ty ty' g Q,
        wp_lval (Evar (Gname g) ty') (fun v => Q (Vptr v))
        |-- wp_operand (Ecast Cfun2ptr Lvalue (Evar (Gname g) ty') ty) Q.

    (** Known places that bitcasts occur
        - casting between [void*] and [T*] for some [T].
     *)
    Axiom wp_operand_cast_bitcast : forall e t Q,
        wp_operand e Q
        |-- wp_operand (Ecast Cbitcast Prvalue e t) Q.

    (** [Cintegral] casts represent casts between integral types, e.g.
        - [int] -> [short]
        - [short] -> [long]
        - [int] -> [unsigned int]
        - [enum Xxx] -> [int]
     *)
    Axiom wp_operand_cast_integral : forall e t Q,
        wp_operand e (fun v free =>
           Exists v', [| exists tu, tu ⊧ resolve /\ conv_int tu (type_of e) t v v' |] ** Q v' free)
        |-- wp_operand (Ecast Cintegral Prvalue e t) Q.

    Axiom wp_operand_cast_null : forall e t Q,
        wp_operand e Q
        |-- wp_operand (Ecast Cnull2ptr Prvalue e t) Q.

    (* note(gmm): in the clang AST, the subexpression is the call.
     * in essence, [Ecast (Cuser ..)] is a syntax annotation.
     *)
    Axiom wp_init_cast_user : forall ty' e p ty Z Q,
        wp_init ty' p e Q
        |-- wp_init ty' p (Ecast (Cuser Z) Prvalue e ty) Q.

    Axiom wp_operand_cast_user : forall e ty Z Q,
        wp_operand e Q
        |-- wp_operand (Ecast (Cuser Z) Prvalue e ty) Q.

    Definition UNSUPPORTED_reinterpret_cast (ty1 ty2 : type) : mpred.
    Proof. exact False%I. Qed.

    (** https://eel.is/c++draft/expr.reinterpret.cast

        NOTE there is a lot of subtlety around [reinterpret_cast]
     *)
    Axiom wp_operand_cast_reinterpret : forall e qt ty Q,
        match (* source *) type_of e , (* target *) qt with
        | Tptr _ , Tnum _ _ =>
          (* https://eel.is/c++draft/expr.reinterpret.cast#4
             A pointer can be explicitly converted to any integral type large
             enough to hold all values of its type. The mapping function is
             implementation-defined. *)
          wp_operand (Ecast Cptr2int Prvalue e ty) Q
        | Tnum _ _ , Tptr _ =>
          (* A value of integral type or enumeration type can be explicitly
             converted to a pointer. A pointer converted to an integer of sufficient
             size (if any such exists on the implementation) and back to the same
             pointer type will have its original value; mappings between pointers
             and integers are otherwise implementation-defined. *)
          wp_operand (Ecast Cint2ptr Prvalue e ty) Q
        | Tnullptr , Tnum _ _ =>
          (* A value of type [std​::​nullptr_t] can be converted to an integral type;
             the conversion has the same meaning and validity as a conversion of
             (void* )0 to the integral type.
           *)
          wp_operand e (fun _ free => Q (Vint 0) free)
        | Tptr (Tnum _ _), Tptr (Tnum W8 _) =>
          (* A narrow special case where the pointer does not change.
             This intentionally avoids the sources of struct pointers and union
             pointers because those might hit the "pointer-interconvertible"
             cases, where the pointer value might change.
           *)
            wp_operand e Q
        | ty1 , ty2 => UNSUPPORTED_reinterpret_cast ty1 ty2
        end
        |-- wp_operand (Ecast (Creinterpret qt) Prvalue e ty) Q.

    (** [Cstatic c] represents a use of `static_cast` to perform the underlying
        cast.
     *)
    Axiom wp_operand_static_cast : forall c vc e ty Q,
          wp_operand (Ecast c vc e ty) Q
      |-- wp_operand (Ecast (Cstatic c) vc e ty) Q.

    Axiom wp_lval_static_cast : forall c vc e ty Q,
          wp_lval (Ecast c vc e ty) Q
      |-- wp_lval (Ecast (Cstatic c) vc e ty) Q.

    Axiom wp_xval_static_cast : forall c vc e ty Q,
          wp_xval (Ecast c vc e ty) Q
      |-- wp_xval (Ecast (Cstatic c) vc e ty) Q.

    (** You can cast anything to void, but an expression of type
        [void] can only be a pr_value *)
    Axiom wp_operand_cast_tovoid : forall vc e Q,
          wp_discard vc e (fun free => Q Vundef free)
      |-- wp_operand (Ecast C2void vc e Tvoid) Q.

    Axiom wp_operand_cast_array2ptr : forall vc e t Q,
        wp_glval vc e (fun p => Q (Vptr p))
        |-- wp_operand (Ecast Carray2ptr vc e t) Q.

    (** [Cptr2int] exposes the pointer, which is expressed with [pinned_ptr]
     *)
    Axiom wp_operand_ptr2int : forall e ty Q,
        match drop_qualifiers (type_of e) , ty with
        | Tptr _ , Tnum sz sgn =>
          wp_operand e (fun v free => Exists p, [| v = Vptr p |] **
            (Forall va, pinned_ptr va p -* Q (Vint (match sgn with
                                                    | Signed => to_signed sz
                                                    | Unsigned => trim (bitsN sz)
                                                    end (Z.of_N va))) free))
        | _ , _ => False
        end
        |-- wp_operand (Ecast Cptr2int Prvalue e ty) Q.

    (** [Cint2ptr] uses "angelic non-determinism" to allow the developer to
        pick any pointer that was previously exposed as the given integer.
     *)
    Axiom wp_operand_int2ptr : forall e ty Q,
        match unptr ty with
        | Some ptype =>
          wp_operand e (fun v free => Exists va : N, [| v = Vint (Z.of_N va) |] **
             (([| (0 < va)%N |] **
               Exists p,
                 pinned_ptr va p **
                 (* NOTE: In the future when we properly handle cv-qualifiers
                    we will need to replace this with some existentially
                    quantified [ptype'] which is less cv-qualified than
                    [ptype].

                    <https://eel.is/c++draft/conv.qual#note-3>
                  *)
                 type_ptr (erase_qualifiers ptype) p **
                 Q (Vptr p) free) \\//
              ([| va = 0%N |] ** Q (Vptr nullptr) free)))
        | _ => False
        end
        |-- wp_operand (Ecast Cint2ptr Prvalue e ty) Q.

    (** * [Cderived2base]
        casts from a derived class to a base class. Casting is only permitted
        on pointers and references
        - references occur with lvalues and xvalues
        - pointers occur with prvalues

        NOTE these casts require a side-condition that the [path] is valid
             in the program. We express this using the [valid_ptr] side
             condition, i.e. [valid_ptr addr] requires that [addr] only
             has valid paths.
             It would technically be a little nicer if this side condition
             was checked at "compile" time rather than at runtime.
     *)
    Axiom wp_lval_cast_derived2base : forall e vc ty path Q,
      match drop_qualifiers (type_of e), drop_qualifiers ty with
      | Tnamed derived , Tnamed base =>
          wp_glval vc e (fun addr free =>
            let addr' := addr ,, derived_to_base derived path in
            valid_ptr addr' ** Q addr' free)
      | _, _ => False
      end
      |-- wp_lval (Ecast (Cderived2base path) vc e ty) Q.

    Axiom wp_xval_cast_derived2base : forall e vc ty path Q,
      match drop_qualifiers (type_of e), drop_qualifiers ty with
      | Tnamed derived , Tnamed base =>
          wp_glval vc e (fun addr free =>
            let addr' := addr ,, derived_to_base derived path in
            valid_ptr addr' ** Q addr' free)
      | _, _ => False
      end
      |-- wp_xval (Ecast (Cderived2base path) vc e ty) Q.

    Axiom wp_operand_cast_derived2base : forall e ty path Q,
      match drop_qualifiers <$> unptr (type_of e), drop_qualifiers <$> unptr  ty with
      | Some (Tnamed derived) , Some (Tnamed base) =>
          wp_operand e (fun addr free =>
            let addr' := _eqv addr ,, derived_to_base derived path in
            valid_ptr addr' ** Q (Vptr addr') free)
      | _, _ => False
        end
      |-- wp_operand (Ecast (Cderived2base path) Prvalue e ty) Q.

    (* [Cbase2derived] casts from a base class to a derived class.
     *)
    Axiom wp_lval_cast_base2derived : forall e vc ty path Q,
      match drop_qualifiers (type_of e), drop_qualifiers ty with
      | Tnamed base , Tnamed derived =>
          wp_glval vc e (fun addr free =>
            let addr' := addr ,, base_to_derived derived path in
            valid_ptr addr' ** Q addr' free)
      | _, _ => False
      end
      |-- wp_lval (Ecast (Cbase2derived path) vc e ty) Q.

    Axiom wp_xval_cast_base2derived : forall e vc ty path Q,
      match drop_qualifiers (type_of e), drop_qualifiers ty with
      | Tnamed base , Tnamed derived =>
          wp_glval vc e (fun addr free =>
            let addr' := addr ,, base_to_derived derived path in
            valid_ptr addr' ** Q addr' free)
      | _, _ => False
      end
      |-- wp_xval (Ecast (Cbase2derived path) vc e ty) Q.

    Axiom wp_operand_cast_base2derived : forall e ty path Q,
         match drop_qualifiers <$> unptr (type_of e), drop_qualifiers <$> unptr ty with
         | Some (Tnamed base), Some (Tnamed derived) =>
          wp_operand e (fun addr free =>
            let addr' := _eqv addr ,, base_to_derived derived path in
            valid_ptr addr' ** Q (Vptr addr') free)
         | _, _ => False
        end
      |-- wp_operand (Ecast (Cbase2derived path) Prvalue e ty) Q.

    (** the ternary operator [_ ? _ : _] has the value category
     * of the "then" and "else" expressions (which must be the same).
     * We express this with 4 rules, one for each of [wp_lval],
     * [wp_operand], [wp_xval], and [wp_init].
     *)
    Definition wp_cond {T} (wp : Expr -> (T -> FreeTemps.t -> epred) -> mpred) : Prop :=
      forall ty tst th el (Q : T -> FreeTemps -> mpred),
        Unfold WPE.wp_test (wp_test tst (fun c free =>
           if c
           then wp th (fun v free' => Q v (free' >*> free))
           else wp el (fun v free' => Q v (free' >*> free))))
        |-- wp (Eif tst th el ty) Q.

    Axiom wp_lval_condition : Reduce (wp_cond wp_lval).
    Axiom wp_xval_condition : Reduce (wp_cond wp_xval).
    Axiom wp_operand_condition : Reduce (wp_cond wp_operand).

    Axiom wp_init_condition : forall ty addr tst th el Q,
        Unfold WPE.wp_test (wp_test tst (fun c free =>
           if c
           then wp_init ty addr th (fun free' frees => Q free' (frees >*> free))
           else wp_init ty addr el (fun free' frees => Q free' (frees >*> free))))
        |-- wp_init ty addr (Eif tst th el ty) Q.

    Axiom wp_operand_implicit : forall e Q,
        wp_operand e Q |-- wp_operand (Eimplicit e) Q.
    Axiom wp_init_implicit : forall ty e p Q,
        wp_init ty p e Q |-- wp_init ty p (Eimplicit e) Q.

    (** Gets the type used in an expression like `sizeof` and `alignof` *)
    Definition get_type (ety : type + Expr) : type :=
      match ety with
      | inl ty => ty
      | inr e => type_of e
      end.

    (** `sizeof(ty)`
        https://eel.is/c++draft/expr.sizeof#1 and https://eel.is/c++draft/expr.sizeof#2
        When applied to a reference type, the size of the referenced type is used.
     *)
    Axiom wp_operand_sizeof : forall ety ty Q,
        Exists sz, [| size_of (drop_reference $ get_type ety) = Some sz |]  ** Q (Vn sz) FreeTemps.id
        |-- wp_operand (Esize_of ety ty) Q.

    (** `alignof(e)`
        https://eel.is/c++draft/expr.alignof
     *)
    Axiom wp_operand_alignof : forall ety ty Q,
        Exists align, [| align_of (drop_reference $ get_type ety) = Some align |] ** Q (Vint (Z.of_N align)) FreeTemps.id
        |-- wp_operand (Ealign_of ety ty) Q.

    (** * Function calls

        The next few axioms rely on the evaluation order specified
        since C++17 (implemented in Clang >= 4):
        to evaluate [f(args)], [f] is evaluated before [args].

        Summary of the change: https://stackoverflow.com/a/38798487/53974.
        Official references (from http://clang.llvm.org/cxx_status.html):
        http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0400r0.html
        http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2016/p0145r3.pdf
     *)

    (** [wp_call pfty f es Q] calls [f] taking the arguments from the
        evaluations of [es] and then acts like [Q].
        [pfty] is the type that the call is being carried out using,
        i.e. the syntactic type of the function (it is a pointer type).

        NOTE that the AST *must* insert implicit casts for casting
             qualifiers so that the types match up exactly up to top-level
             qualifiers, e.g. [foo(const int)] will be passed a value of
             type [int] (not [const int]). the issue with type-level
             qualifiers is addressed through the use of [normalize_type]
             below.
     *)
    Definition wp_call (pfty : type) (f : val) (es : list Expr) (Q : ptr -> FreeTemps -> epred) : mpred :=
      match unptr pfty with
      | Some fty =>
        let fty := normalize_type fty in
        Exists fp, [| f = Vptr fp |] **
        match arg_types fty with
        | Some targs =>
          wp_args targs es $ fun vs free => |> fspec fty fp vs (fun v => Q v free)
        | _ => False
        end
      | None => False
      end.

    Lemma wp_call_frame pfty f es Q Q' :
      Forall p free, Q p free -* Q' p free |-- wp_call pfty f es Q -* wp_call pfty f es Q'.
    Proof.
      rewrite /wp_call.
      case_match; eauto.
      case_match; eauto.
      iIntros "K X"; iDestruct "X" as (y) "X"; iExists y; iDestruct "X" as "[$ X]".
      iRevert "X"; iApply wp_args_frame.
      iIntros (??).
      iIntros "X"; iNext; iRevert "X".
      iApply fspec_frame.
      iIntros (?); iApply "K".
    Qed.

    Axiom wp_lval_call : forall f (es : list Expr) Q (ty : type),
        wp_operand f (fun fn free_f => wp_call (type_of f) fn es $ fun res free_args =>
           Reduce (lval_receive ty res $ fun v => Q v (free_args >*> free_f)))
        |-- wp_lval (Ecall f es ty) Q.

    Axiom wp_xval_call : forall f (es : list Expr) Q (ty : type),
        wp_operand f (fun fn free_f => wp_call (type_of f) fn es $ fun res free_args =>
           Reduce (xval_receive ty res $ fun v => Q v (free_args >*> free_f)))
        |-- wp_xval (Ecall f es ty) Q.

    Axiom wp_operand_call : forall ty f es Q,
        wp_operand f (fun fn free_f => wp_call (type_of f) fn es $ fun res free_args =>
           Reduce (operand_receive ty res $ fun v => Q v (free_args >*> free_f)))
       |-- wp_operand (Ecall f es ty) Q.

    Axiom wp_init_call : forall f es Q (addr : ptr) ty ty',
          (* ^ give the memory back to the C++ abstract machine *)
          wp_operand f (fun fn free_f => wp_call (type_of f) fn es $ fun res free_args =>
             Reduce (init_receive ty addr res $ fun free => Q ty (free_args >*> free_f)))
      |-- wp_init ty addr (Ecall f es ty') Q.

    (** * Member calls *)
    Definition member_arg_types (fty : type) : option (list type) :=
      match fty with
      | Tfunction _ (_ :: args) => Some args
      | _ => None
      end.

    (** [wp_mcall f this this_type fty es Q] calls member function pointed to by
        [f] (of type [fty], after stripping the member pointer) on [this] (of
        type [this_type]) using arguments [es] and continues with [Q].

        NOTE that the AST *must* insert implicit casts for casting qualifiers so
             that the types match up exactly up to top-level qualifiers, e.g.
             [foo(const int)] will be passed a value of type [int] (not [const
             int]). the issue with type-level qualifiers is addressed through
             the use of [normalize_type] below. *)
    Definition wp_mcall (f : val) (this : ptr) (this_type : type) (fty : type) (es : list Expr)
               (Q : ptr -> FreeTemps -> epred) : mpred :=
      let fty := normalize_type fty in
      Exists fp, [| f = Vptr fp|] **
      match arg_types fty with
      | Some targs =>
        wp_args targs es $ fun vs free => |> mspec this_type fty fp (this :: vs) (fun v => Q v free)
      | _ => False
      end.

    Lemma wp_mcall_frame f this this_type fty es Q Q' :
      Forall p free, Q p free -* Q' p free |-- wp_mcall f this this_type fty es Q -* wp_mcall f this this_type fty es Q'.
    Proof.
      rewrite /wp_mcall.
      case_match; eauto.
      iIntros "K X"; iDestruct "X" as (y) "X"; iExists y; iDestruct "X" as "[$ X]".
      iRevert "X"; iApply wp_args_frame.
      iIntros (??).
      iIntros "X"; iNext; iRevert "X".
      iApply fspec_frame.
      iIntros (?); iApply "K".
    Qed.

    Axiom wp_lval_member_call : forall ty fty f vc obj es Q,
        wp_glval vc obj (fun this free_this => wp_mcall (Vptr $ _global f) this (type_of obj) fty es $ fun res free_args =>
           lval_receive ty res $ fun v => Q v (free_args >*> free_this))
        |-- wp_lval (Emember_call (inl (f, Direct, fty)) vc obj es ty) Q.

    Axiom wp_xval_member_call : forall ty fty f vc obj es Q,
        wp_glval vc obj (fun this free_this => wp_mcall (Vptr $ _global f) this (type_of obj) fty es $ fun res free_args =>
           xval_receive ty res $ fun v => Q v (free_args >*> free_this))
        |-- wp_xval (Emember_call (inl (f, Direct, fty)) vc obj es ty) Q.

    Axiom wp_operand_member_call : forall ty fty f vc obj es Q,
        wp_glval vc obj (fun this free_this => wp_mcall (Vptr $ _global f) this (type_of obj) fty es $ fun res free_args =>
           operand_receive ty res $ fun v => Q v (free_args >*> free_this))
        |-- wp_operand (Emember_call (inl (f, Direct, fty)) vc obj es ty) Q.

    Axiom wp_init_member_call : forall f fty es (addr : ptr) ty vc obj Q,
        wp_glval vc obj (fun this free_this => wp_mcall (Vptr $ _global f) this (type_of obj) fty es $ fun res free_args =>
           init_receive ty addr res $ fun free => Q ty (free_args >*> free_this))
        |-- wp_init ty addr (Emember_call (inl (f, Direct, fty)) vc obj es ty) Q.

    (** virtual functions
        these are slightly more complex because we need to compute the address of the function
        using the most-derived-class of the [this] object. This is done using [resolve_virtual].

        NOTE The [resolve_virtual] below means that caller justifies the cast to the dynamic type.
             This is necessary because the function is expecting the correct [this] pointer.

        [tq] is passed on to [wp_mcall] because that contains the information whether or not
        the called method is a [const] method. This matches the construction of [SMethod].
     *)
    Definition wp_virtual_call (f : obj_name) (this : ptr) (this_type : type) (fty : type) (es : list Expr)
               (Q : ptr -> FreeTemps -> epred) : mpred :=
      match decompose_type this_type with
      | (tq, Tnamed cls) =>
        resolve_virtual this cls f (fun fimpl_addr impl_class thisp => (* this would have to go away *)
            wp_mcall (Vptr fimpl_addr) thisp (tqualified tq (Tnamed impl_class)) fty es $ fun res free_args => Q res free_args)
      | _ => False
      end.

    Axiom wp_xval_virtual_call : forall ty fty f vc obj es Q,
        wp_glval vc obj (fun this free_this => wp_virtual_call f this (type_of obj) fty es $ fun res free_args =>
                   xval_receive ty res $ fun v => Q v (free_args >*> free_this))
      |-- wp_xval (Emember_call (inl (f, Virtual, fty)) vc obj es ty) Q.

    Axiom wp_lval_virtual_call : forall ty fty f vc obj es Q,
        wp_glval vc obj (fun this free_this => wp_virtual_call f this (type_of obj) fty es $ fun res free_args =>
                   lval_receive ty res $ fun v => Q v (free_args >*> free_this))
      |-- wp_lval (Emember_call (inl (f, Virtual, fty)) vc obj es ty) Q.

    Axiom wp_operand_virtual_call : forall ty fty f vc obj es Q,
        wp_glval vc obj (fun this free_this => wp_virtual_call f this (type_of obj) fty es $ fun res free_args =>
           operand_receive ty res $ fun v => Q v (free_args >*> free_this))
        |-- wp_operand (Emember_call (inl (f, Virtual, fty)) vc obj es ty) Q.

    Axiom wp_init_virtual_call : forall f fty es (addr : ptr) ty vc obj Q,
        wp_glval vc obj (fun this free_this => wp_virtual_call f this (type_of obj) fty es $ fun res free_args =>
           init_receive ty addr res $ fun free => Q ty (free_args >*> free_this))
        |-- wp_init ty addr (Emember_call (inl (f, Virtual, fty)) vc obj es ty) Q.

    (* null *)
    Axiom wp_null : forall Q,
      Q (Vptr nullptr) FreeTemps.id
      |-- wp_operand Enull Q.

    (** The lifetime of an object can be ended at an arbitrary point
        without calling the destructor
        (http://eel.is/c++draft/basic.life#5). According to
        http://eel.is/c++draft/basic.life#5, a program has UB if it
        depends on the side effects of the destructor if it is not
        explicitly called before the storage is reused. This is
        reflected here by not doing the ownership manipulation that
        the destructor would potentially do. *)
    Axiom end_provides_storage : forall storage_ptr obj_ptr aty sz,
       size_of aty = Some sz ->
       provides_storage storage_ptr obj_ptr aty ** obj_ptr |-> anyR aty 1
         ={⊤}=∗ (storage_ptr |-> blockR sz 1).

    (** temporary expressions
       note(gmm): these axioms should be reviewed thoroughly
     *)
    (* Clang's documentation for [ExprWithCleanups] states:

       > Represents an expression – generally a full-expression – that
       > introduces cleanups to be run at the end of the sub-expression's
       > evaluation.

       Therefore, we destroy temporaries created when evaluating [e]
       before running the continuation.

       NOTE: We follow C++'s AST rules for destroying temporaries appropriately
       so these nodes should effectively be no-ops, though there are certain
       places in the AST that has odd evaluation semantics
     *)
    Axiom wp_lval_clean : forall e Q,
          wp_lval e (fun p frees => interp frees $ Q p FreeTemps.id)
      |-- wp_lval (Eandclean e) Q.
    Axiom wp_xval_clean : forall e Q,
          wp_xval e (fun p frees => interp frees $ Q p FreeTemps.id)
      |-- wp_xval (Eandclean e) Q.
    Axiom wp_operand_clean : forall e Q,
          wp_operand e (fun v frees => interp frees $ Q v FreeTemps.id)
      |-- wp_operand (Eandclean e) Q.
    Axiom wp_init_clean : forall ty e addr Q,
          wp_init ty addr e (fun free frees => interp frees $ Q free FreeTemps.id)
      |-- wp_init ty addr (Eandclean e) Q.

    (** [Ematerialize_temp e ty] is an xvalue that gets memory (with automatic
        storage duration) and initializes it using the expression.
     *)
    Axiom wp_xval_temp : forall e Q,
        (let ty := type_of e in
         Forall a : ptr,
         wp_initialize ty a e (fun frees => Q a (FreeTemps.delete ty a >*> frees)))
        |-- wp_xval (Ematerialize_temp e) Q.

    Axiom wp_lval_temp : forall e Q,
        (let ty := type_of e in
         Forall a : ptr,
         wp_initialize ty a e (fun frees => Q a (FreeTemps.delete ty a >*> frees)))
        |-- wp_lval (Ematerialize_temp e) Q.

    (** Pseudo destructors arise from calling the destructor on
        an object of templated type when the type is instantiated
        with a primitive. For example,

          template<typename T> void destroy_it(T* t) { t->~T(); }

        with [T = int].

        To maintain similarity with the rest of the system, we
        the C++ abstract machine "implements" these destructors as
        (essentially) a function with the specification:

           \pre this |-> anyR ty 1
           \post this |-> tblockR ty

        Note that the memory is *not* returned to the C++ abstract
        machine because this is not reclaimation for an object going
        out of scope.
     *)
    Axiom wp_operand_pseudo_destructor : forall e ty Q,
        wp_lval e (fun v free => v |-> anyR ty 1 ** (v |-> tblockR ty 1 -* Q Vvoid free))
        |-- wp_operand (Epseudo_destructor ty e) Q.

    (* `Eimplicit_init` nodes reflect implicit /value initializations/ which are inserted
       into the AST by Clang [1]. The C++ standard states that value initializations [2]
       are equivalent to zero initializations for non-class and non-array types [3];
       zero initializations are documented here [4].

       [1] https://clang.llvm.org/doxygen/classclang_1_1ImplicitValueInitExpr.html#details
       [2] https://eel.is/c++draft/dcl.init#general-8
       [3] https://eel.is/c++draft/dcl.init#general-8.3
       [4] https://eel.is/c++draft/dcl.init#general-6
     *)
    Axiom wp_operand_implicit_init_int : forall ty sz sgn Q,
        drop_qualifiers ty = Tnum sz sgn ->
          Q (Vint 0) FreeTemps.id
      |-- wp_operand (Eimplicit_init ty) Q.

    Axiom wp_operand_implicit_init_bool : forall ty Q,
        drop_qualifiers ty = Tbool ->
          Q (Vbool false) FreeTemps.id
      |-- wp_operand (Eimplicit_init ty) Q.

    Axiom wp_init_constructor : forall cls (addr : ptr) cnd es Q,
        (* NOTE because the AST does not include the types of the arguments of
           the constructor, we have to look up the type in the environment.
         *)
           match tu !! cnd with
           | Some cv =>
             addr |-> tblockR (Tnamed cls) 1 -*
             (* ^^ The semantics currently has constructors take ownership of a [tblockR] *)
             wp_mcall (Vptr $ _global cnd) addr (Tnamed cls) (type_of_value cv) es (fun p free =>
               (* in the semantics, constructors return [void] *)
               p |-> primR Tvoid 1 Vvoid ** Q (Tnamed cls) free)
           | _ => False
           end
      |-- wp_init (Tnamed cls) addr (Econstructor cnd es (Tnamed cls)) Q.

    Fixpoint wp_array_init (ety : type) (base : ptr) (es : list Expr) (idx : Z) (Q : FreeTemps -> mpred) : mpred :=
      match es with
      | nil =>
        base .[ ety ! idx ] |-> validR -* Q FreeTemps.id
      | e :: rest =>
          (* NOTE: We nest the recursive calls to `wp_array_init` within
               the continuation of the `wp_initialize` statement to
               reflect the fact that the C++ Standard introduces
               sequence-points between all of the elements of an
               initializer list (c.f. http://eel.is/c++draft/dcl.init.list#4)

               NOTE the use of [wp_initialize] here is essentially the same as [wp_init]
               because you can not have arrays of reference-type.
           *)
         wp_initialize ety (base .[ ety ! idx ]) e
                       (fun free => interp free $ wp_array_init ety base rest (Z.succ idx) Q)
      end.

    Lemma wp_array_init_frame ety base : forall es ix Q Q',
      (Forall f, Q f -* Q' f)
      |-- wp_array_init ety base es ix Q -*
          wp_array_init ety base es ix Q'.
    Proof.
      induction es; simpl; intros; iIntros "X".
      { iIntros "A B"; iApply "X"; iApply "A"; done. }
      { iApply wp_initialize_frame; iIntros (?).
        iApply interp_frame. by iApply IHes. }
    Qed.

    Definition fill_initlist (desiredsz : N) (es : list Expr) (f : Expr) : list Expr :=
      let actualsz := N.of_nat (length es) in
      es ++ replicateN (desiredsz - actualsz) f.

    (** NOTE this assumes that the C++ abstract machine already owns the array
        that is being initialized, see [wp_init_initlist_array] *)
    Definition wp_array_init_fill (ety : type) (base : ptr) (es : list Expr) (f : option Expr) (sz : N)
               (Q : FreeTemps -> mpred) : mpred :=
      let len := N.of_nat (length es) in
      match (len ?= sz)%N with
      | Lt =>
          match f with
          | None => False
          | Some fill => wp_array_init ety base (fill_initlist sz es fill) 0 Q
          end
      | Eq => wp_array_init ety base es 0 Q
      (* <http://eel.is/c++draft/dcl.init.general#16.5>

         Programs which contain more initializer expressions than
         array-members are ill-formed.
       *)
      | Gt => False
      end.

    Lemma wp_array_init_fill_frame ety base es f sz Q Q' :
      (Forall f, Q f -* Q' f)
      |-- wp_array_init_fill ety base es f sz Q -*
          wp_array_init_fill ety base es f sz Q'.
    Proof.
      rewrite /wp_array_init_fill.
      case_match; eauto.
      { iIntros "X"; iApply wp_array_init_frame. done. }
      { case_match; eauto.
        iApply wp_array_init_frame. }
    Qed.

    (** [is_array_of aty ety] checks that [aty] is a type representing an
        array of [ety].
        NOTE that cpp2v currently prints the type `int[]` as [int* const]
             so we also permit that type.
     *)
    Definition is_array_of (aty ety : type) : Prop :=
      match aty with
      | Tarray ety' _ => ety = ety'
      | Tptr ety' => ety = ety'
      | _ => False
      end.

    (** Initializing an array using an initializer list.
        In the clang AST, the types [ty] and [Tarray ety sz] are now always the
        same, in particular, in the expression `new C[10]{}`. We say that
        the index to [wp_init] is the dynamic type and [type_of (Einitlist ..)]
        is the static type. For santity, we require that the general shape of the
        two types match, but we pull the size of the array from the dynamic type.
     *)
    Axiom wp_init_initlist_array :forall ls fill ty ety (sz : N) (base : ptr) Q, (* sz' <= sz *)
          is_array_of ty ety ->
          wp_array_init_fill ety base ls fill sz (Q (Tarray ety sz))
      |-- wp_init (Tarray ety sz) base (Einitlist ls fill ty) Q.


    (* https://eel.is/c++draft/dcl.init#general-7.2 says that "To
    default-initialize an object of type T means: If T is an array type, each
    element is default-initialized." Clang emits [Econstructor ... (Tarray
    (Tnamed ...))] initializing expressions for those cases, where the
    Econstructor node indicates the constructor for the *elements* in the
    array.

    We assume that the elements of the array are initialized from
    left to right, i.e. from the first element to the last element. The
    standard is not explicit about the initialization order for default
    initialization of arrays, but the standard does explicitly specify this
    ordering for arrays with an explicit element list
    (https://eel.is/c++draft/dcl.init#general-15.5). The standard also demands
    destructors to be run in opposite order (https://eel.is/c++draft/dcl.init.general#19),
    and it's expected that every object "is destroyed in the exact reverse order
    it was constructed." (https://doi.org/10.1145/2103656.2103718,
    https://eel.is/c++draft/expr.delete#6). Therefore, it seems
    reasonable to assume that the same ordering applies for default
    initialization. For this reason, the rule for default initalization
    simply defers to the rule for initialization with an empty initializer
    list. *)
    Axiom wp_init_default_array : forall ty ety sz base ctorname args Q,
          is_array_of ty ety ->
          wp_init ty base (Einitlist [] (Some (Econstructor ctorname args ety)) (Tarray ety sz)) Q
      |-- wp_init (Tarray ety sz) base (Econstructor ctorname args ty) Q.

    Axiom wp_operand_initlist_default : forall t Q,
          match get_default t with
          | None => False
          | Some v => Q v FreeTemps.id
          end
      |-- wp_operand (Einitlist nil None t) Q.

    Axiom wp_operand_initlist_prim : forall t e Q,
          (if prim_initializable t
           then wp_operand e Q
           else False)
      |-- wp_operand (Einitlist (e :: nil) None t) Q.

    (** Initialize the fields of the class [cls] (at [base]) using the
        expressions [es] and then proceed as [Q].
     *)
    Fixpoint init_fields (cls : globname) (base : ptr)
      (fs : list (type * offset)) (es : list Expr) (Q : epred) {struct fs} : mpred :=
      match fs , es with
      | nil , nil => Q
      | (ty, off) :: fs , e :: es =>
          (* note that there is a sequence point after each element initialization.
             See <https://eel.is/c++draft/dcl.init.aggr#7>
           *)
          wp_initialize ty (base ,, off) e
             (fun free => interp free $ init_fields cls base fs es Q)
      | _ , _ => False
      end.

    Lemma init_fields_frame cls base : forall fs es Q Q',
        Q -* Q' |-- init_fields cls base fs es Q -* init_fields cls base fs es Q'.
    Proof.
      induction fs; simpl; intros; repeat case_match; eauto.
      iIntros "X"; iApply wp_initialize_frame.
      iIntros (?); iApply interp_frame.
      by iApply IHfs.
    Qed.

    (** Using an initializer list to create a `struct` or `union`.

       NOTE clang elaborates the initializer list to directly match the members
       of the target class. For example, consider `struct C { int x; int y{3}; };`
       1. `{0}` is elaborated into `{0, 3}`;
       2. `{.y = 7, .x = 2}` is elaborated into `{2, 7}`

       Base classes are also elements. See https://eel.is/c++draft/dcl.init.aggr#2.2

       Note: the C++ standard text provides a special caveat for members
       of anonymous unions, but cpp2v represents anonymous unions as regular
       named unions and the front-end desugars initializer lists accordingly.
     *)
    Axiom wp_init_initlist_agg : forall cls (base : ptr) es t Q,
        let mem_to_li m := (m.(mem_type), o_field _ {| f_type := cls ; f_name := m.(mem_name) |}) in
        let base_to_li '(base,_) := (Tnamed base, o_base _ cls base) in
        match tu !! cls with
        | Some (Gstruct s) =>
            (* these constraints are enforced by clang, see note above *)
            [| length s.(s_bases) + length s.(s_fields) = length es |] **
            let fs :=
              map base_to_li s.(s_bases) ++ map mem_to_li s.(s_fields) in
            init_fields cls base fs es
               (base |-> struct_paddingR 1 cls **
                (if has_vtable s then base |-> identityR cls [cls] 1 else emp) -*
                Q (Tnamed cls) FreeTemps.id)

        | Some (Gunion u) =>
            (* The standard allows initializaing unions in a variety of ways.
               See https://eel.is/c++draft/dcl.init.aggr#5. However, the cpp2v
               frontent desugars all of these to initialize exactly one element.
             *)
            [| length es = 1 |] **
            let fs := map mem_to_li $ firstn 1 u.(u_fields) in
            init_fields cls base fs es
               (base |-> union_paddingR 1 cls (Some 0) -*
                Q (Tnamed cls) FreeTemps.id)
        | _ => False
        end
      |-- wp_init (Tnamed cls) base (Einitlist es None t) Q.

  End with_resolve.

  (* `Earrayloop_init` needs to extend the region, so we need to start a new section. *)
  Section with_resolve__arrayloop.
    Context `{Σ : cpp_logic thread_info} {σ : genv}.
    Variable (tu : translation_unit).

    #[local] Notation interp := (interp tu).

    (* `Earrayloop_init` and `Earrayloop_index` correspond, respectively,
       to the `ArrayInitLoopExpr`[1] and `ArrayInitIndexExpr`[2] expressions
       from clang. While these expressions are not a part of the C++ standard,
       we can still ascribe a useful semantics.

       In particular, this is a restricted loop so we ascribe the semantics by
       unrolling. On each iteration, the C++ Abstract Machine binds a distinguished
       variable ("!loop_index", which is not a valid identifier in C++) so that
       `Earrayloop_index` can read the value. We semantically treat this variable
       as a constant, so we only give `1/2` fraction to it and demand it back at the
       end of each iteration, preferring to do the incrementing in the logic rather
       than using the program syntax.

       For example, the following `Earrayloop_init` expression has the same
       semantics as the C++ loop which follows it /except/ that the array
       we are initializing is only evaluated once (c.f. [1]):
       ```
       (* Coq *)
       Earrayloop_init 16 target init (Tarray ``::uint8`` 16)

       (* C++ *)
       for (int "!loop_index" = 0; "!loop_index" < 16; "!loop_index"++) {
           target["!loop_index"] = init;
       }
       ```

       [1] https://clang.llvm.org/doxygen/classclang_1_1ArrayInitLoopExpr.html#details
       [2] https://clang.llvm.org/doxygen/classclang_1_1ArrayInitIndexExpr.html#details
     *)

    (* A very simple mangling of numbers to strings. Soundness only requires this to be
       injective and we don't expect the [N] to be very large in practice so we pick
       a very naive encoding.
     *)
    Definition N_to_bs (n : N) : bs :=
      N.peano_rect (fun _ => bs)
                   BS.EmptyString
                   (fun _ x => BS.String "1" x) n.

    Definition arrayloop_loop_index (n : N) : bs := "!loop_index" ++ N_to_bs n.
    Definition opaque_val (n : N) : bs := "%opaque" ++ N_to_bs n.

    (* Maybe we can `Rbind (opaque n) p`, and then add `_opaque` to encapsulate looking this up in the region;
       the new premise would be (after Loc:=ptr goes in) `Q _opaque` *)
    Axiom wp_glval_opaque_ref : forall vc n ρ ty Q,
          wp_lval tu ρ (Evar (Lname (opaque_val n)) ty) Q
      |-- wp_glval tu ρ vc (Eopaque_ref n ty) Q.

    (* Maybe do something similar to what was suggested for `wp_lval_opaque_ref` above. *)
    Axiom wp_operand_arrayloop_index : forall ρ level ty Q,
          Exists v,
            ((Exists q, _local ρ (arrayloop_loop_index level)
                               |-> primR (erase_qualifiers ty) q v) **
              True) //\\ Q v FreeTemps.id
      |-- wp_operand tu ρ (Earrayloop_index level ty) Q.

    (* The following loop is essentially the following:
       recursion of `sz`:
       ```
       Fixpoint _arrayloop_init
                (ρ : region) (level : N)
                (targetp : ptr) (init : Expr)
                (ty : type) (Q : FreeTemps -> epred)
                (sz : nat) (idx : N)
                {struct sz}
         : mpred :=
         let loop_index := _local ρ (loop_index level) in
         match sz with
         | O => Q emp
         | S sz' =>
           _at loop_index (primR Tu64 (1/2) idx) -*
           wp_init ρ ty (Vptr $ _offset_ptr targetp $ o_sub resolve ty idx) init
                   (fun free => free **
                      _at loop_index (primR Tu64 (1/2) idx) **
                      _arrayloop_init level sz' ρ (S idx) targetp init ty Q)
         end%I.
       ```

       We use `N.peano_rect` to avoid potentially building a large natural number.
     *)
    Definition _arrayloop_init
               (ρ : region) (level : N)
               (targetp : ptr) (init : Expr)
               (ty : type) (Q : epred)
               (* The arguments above this comment are constant throughout the recursion.

                  The arguments below this line will change during the recursion.
                *)
               (sz : N) (idx : N)
      : mpred :=
      let loop_index := _local ρ (arrayloop_loop_index level) in
      N.peano_rect (fun _ : N => N -> mpred)
                   (fun _ => Q)
                   (fun _ rest idx =>
                      (* NOTE The abstract machine only provides 1/2 of the ownership
                           to the program to make it read-only.
                         NOTE that no "correct" program will ever modify this variable
                           anyways. *)
                      loop_index |-> primR Tu64 (1/2) idx -*
                      wp_initialize tu ρ ty (targetp .[ ty ! idx ]) init
                              (fun free => interp free $
                                 loop_index |-> primR Tu64 (1/2) idx **
                                 rest (N.succ idx))) sz idx.

    Axiom wp_init_arrayloop_init : forall oname level sz ρ (trg : ptr) vc src init ety ty Q,
          has_type (Vn sz) Tu64 ->
          is_array_of ty ety ->
          wp_glval tu ρ vc src
                   (fun p free =>
                      Forall idxp,
                      trg |-> validR -*
                      _arrayloop_init (Rbind (opaque_val oname) p
                                             (Rbind (arrayloop_loop_index level) idxp ρ))
                                      level trg init ety
                                      (Q (Tarray ety sz) free)
                                      sz 0)
      |-- wp_init tu ρ (Tarray ety sz) trg
                    (Earrayloop_init oname vc src level sz init ty) Q.

  End with_resolve__arrayloop.
End Expr.

Declare Module E : Expr.

Export E.
