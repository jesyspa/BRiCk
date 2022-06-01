(*
 * Copyright (c) 2019-2022 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)
Require Import Coq.ZArith.ZArith.

Require bedrock.lang.cpp.ast.
From bedrock.lang.cpp.syntax Require Import names types.

#[local] Open Scope Z_scope.
#[local] Open Scope bs_scope.

(* NOTE (JH): [tests/type_notation_tests.v] contains tests of parsing/printing notations
   as well as [Check]s whose output is compared against a reference file.
 *)

Module Export TypeNotations.
  Declare Custom Entry CPP_type.
  Declare Scope CPP_type_scope.
  Delimit Scope CPP_type_scope with cpp_type.
  (* TODO (JH): Determine if we want (something like) this, and then do it. *)
  Bind Scope CPP_type_scope with type.

  (* Injection into [constr] in case we're printing this at the top-level *)
  Notation "'{(t:' ty ')}'"
      := ty
         ( at level 200
         , ty custom CPP_type at level 200
         , format "'[hv' {(t:  '/' ty )} ']'")
       : CPP_type_scope.
  (* Injection from [constr] in case we're printing a subterm we don't recognize *)
  Notation "'{(coq:' ty ')}'"
      := ty
         ( in custom CPP_type at level 0
         , ty constr
         , format "'[hv' {(coq:  '/' ty )} ']'").

  (* [type_qualifiers] - leaf nodes get the highest priority *)
  Notation "'mut'" := QM (in custom CPP_type at level 0).
  Notation "'const'" := QC (in custom CPP_type at level 0).
  Notation "'volatile'" := QV (in custom CPP_type at level 0).
  Notation "'const' 'volatile'"
      := QCV
         ( in custom CPP_type at level 0
         , format "'[' const  volatile ']'").

  (* [Tqualified] types *)
  Notation "'mut' ty"
      := (Qmut ty)
         ( in custom CPP_type at level 100
         , ty custom CPP_type at level 200
         , right associativity
         , format "'[' mut  ty ']'").
  Notation "'const' ty"
      := (Qconst ty)
         ( in custom CPP_type at level 100
         , ty custom CPP_type at level 200
         , right associativity
         , format "'[' const  ty ']'").
  Notation "'volatile' ty"
      := (Qmut_volatile ty)
         ( in custom CPP_type at level 100
         , ty custom CPP_type at level 200
         , right associativity
         , format "'[' volatile  ty ']'").
  Notation "'const' 'volatile' ty"
      := (Qconst_volatile ty)
         ( in custom CPP_type at level 100
         , ty custom CPP_type at level 200
         , right associativity
         , format "'[' const  volatile  ty ']'").

  (* [Tnum] variants *)
  Notation "'int8'" := Ti8 (in custom CPP_type at level 0).
  Notation "'uint8'" := Tu8 (in custom CPP_type at level 0).
  Notation "'int16'" := Ti16 (in custom CPP_type at level 0).
  Notation "'uint16'" := Tu16 (in custom CPP_type at level 0).
  Notation "'int32'" := Ti32 (in custom CPP_type at level 0).
  Notation "'uint32'" := Tu32 (in custom CPP_type at level 0).
  Notation "'int64'" := Ti64 (in custom CPP_type at level 0).
  Notation "'uint64'" := Tu64 (in custom CPP_type at level 0).
  Notation "'int128'" := Ti128 (in custom CPP_type at level 0).
  Notation "'uint128'" := Tu128 (in custom CPP_type at level 0).

  (* The rest of the [type]s *)
  Notation "'ptr<' ty '>'"
      := (Tptr ty)
         ( in custom CPP_type at level 100
         , ty custom CPP_type at level 200
         , left associativity
         , format "'[' ptr< ty > ']'").
  Notation "'ref&<' ty '>'"
      := (Tref ty)
         ( in custom CPP_type at level 100
         , ty custom CPP_type at level 200
         , left associativity
         , format "'[' ref&< ty > ']'").
  Notation "'ref&&<' ty '>'"
      := (Trv_ref ty)
         ( in custom CPP_type at level 100
         , ty custom CPP_type at level 200
         , left associativity
         , format "'[' ref&&< ty > ']'").
  Notation "'void'" := Tvoid (in custom CPP_type at level 0).
  Notation "ty [ n ]"
      := (Tarray ty n%N)
         ( in custom CPP_type at level 80
         , ty custom CPP_type
         , n constr
         , format "'[' ty [ n ] ']'").
  Notation "nm" := (Tnamed nm%bs) (in custom CPP_type at level 0, nm constr).
  Notation "'extern' cc '???()' '->' rty"
      := (@Tfunction cc Ar_Definite rty nil)
         ( in custom CPP_type at level 100
         , cc constr at level 0
         , rty custom CPP_type at level 200
         , format "'[' extern  cc  ???()  ->  rty ']'").
  Notation "'extern' cc '???(' aty1 , .. , aty2 ')' '->' rty"
      := (@Tfunction cc Ar_Definite rty (cons aty1 .. (cons aty2 nil) ..))
         ( in custom CPP_type at level 100
         , cc constr at level 0
         , rty custom CPP_type at level 200
         , aty1 custom CPP_type at level 200
         , aty2 custom CPP_type at level 200
         , format "'[' extern  cc  ???( '[hv' aty1 ,  '/' .. ,  '/' aty2 ']' )  ->  rty ']'").
  Notation "'extern' cc '???()(...)' '->' rty"
      := (@Tfunction cc Ar_Variadic rty nil)
         ( in custom CPP_type at level 100
         , cc constr at level 0
         , rty custom CPP_type at level 200
         , format "'[' extern  cc  ???()(...)  ->  rty ']'").
  Notation "'extern' cc '???(' aty1 , .. , aty2 ')(...)' '->' rty"
      := (@Tfunction cc Ar_Variadic rty (cons aty1 .. (cons aty2 nil) ..))
         ( in custom CPP_type at level 100
         , cc constr at level 0
         , rty custom CPP_type at level 200
         , aty1 custom CPP_type at level 200
         , aty2 custom CPP_type at level 200
         , format "'[' extern  cc  ???( '[hv' aty1 ,  '/' .. ,  '/' aty2 ']' )(...)  ->  rty ']'").
  Notation "'bool'" := Tbool (in custom CPP_type at level 0).
  Notation "'ptr[' nm ']<' ty '>'"
      := (Tmember_pointer nm%bs ty)
         ( in custom CPP_type at level 100
         , nm constr
         , ty custom CPP_type
         , left associativity
         , format "'[' ptr[ nm ]< ty > ']'").
  Notation "'{float:' sz '}'"
      := (Tfloat sz)
         ( in custom CPP_type at level 0
         , sz constr
         , format "'[hv' {float:  '/' sz } ']'").
  Notation "'(' qual ty ')'"
      := (Tqualified qual ty)
         ( in custom CPP_type at level 100
         , qual custom CPP_type at level 0
         , ty custom CPP_type at level 200
         , format "'[' ( qual  ty ) ']'").
  Notation "'nullptr_t'" := Tnullptr (in custom CPP_type at level 0).
  Notation "'{arch:' nm '}'"
      := (Tarch None nm%bs)
         ( in custom CPP_type at level 0
         , nm constr
         , format "'[hv' {arch:  '/' nm } ']'").
  Notation "'{arch:' nm ';' 'size:' sz '}'"
      := (Tarch (Some sz) nm%bs)
         ( in custom CPP_type at level 0
         , sz constr
         , nm constr
         , format "'[hv' {arch:  nm ;  '/' size:  sz } ']'").
End TypeNotations.
