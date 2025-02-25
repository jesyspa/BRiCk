(*
 * Copyright (c) 2020-21 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)
(*
 * The following code contains code derived from code original to the
 * stdpp project. That original code is
 *
 *	Copyright stdpp developers and contributors
 *
 * and used according to the following license.
 *
 *	SPDX-License-Identifier: BSD-3-Clause
 *
 * Original stdpp License:
 * https://gitlab.mpi-sws.org/iris/stdpp/-/blob/5415ad3003fd4b587a2189ddc2cc29c1bd9a9999/LICENSE
 *)

From stdpp Require Import base decidable countable.
From bedrock.prelude Require Import base option list_numbers finite.

#[local] Open Scope N_scope.

Implicit Types (n : N) (p : positive).

Module fin.
  Definition t n := {m : N | m < n}.

  Lemma t_0_inv : t 0 -> False.
  Proof. by inversion 1; lia. Qed.

  Definition of_N (p : positive) (n : N) : t (Npos p) :=
    match decide (n < Npos p) with
    | left prf => n ↾ prf
    | right _ => 0 ↾ eq_refl
    end.
  Definition to_N {n} (f : t n) : N := `f.

  Definition t_eq {n} (x1 x2 : t n)
    (Heq : to_N x1 = to_N x2) : x1 = x2.
  Proof. apply /sig_eq_pi /Heq. Qed.

  Lemma to_of_N (p : positive) (n : N) : n < N.pos p -> to_N (of_N p n) = n.
  Proof. rewrite /fin.of_N. by case_match. Qed.

  Lemma of_to_N {p} (x : t (N.pos p)) : of_N p (to_N x) = x.
  Proof. apply t_eq, to_of_N. by case: x. Qed.

  (** Declared an instance, because it is not redudant after [t] is made opaque. *)
  #[global] Instance to_N_inj n : Inj eq eq (to_N (n := n)) := _.
  #[global] Instance t_eq_dec n : EqDecision (t n) := _.
  #[global] Instance t_countable n : Countable (t n) := _.

  #[global] Instance t_pos_inhabited p : Inhabited (t (Npos p)) := populate (of_N _ 0).

  (* More flexible variant of [t_pos_inhabited]. *)
  Lemma t_gt_inhabited n : 0 < n -> Inhabited (t n).
  Proof. case: n; [lia|]; apply _. Qed.

  #[global] Hint Opaque t : typeclass_instances.

  (** The [mk m] notation works if both [m] and the bound [n] are ground,
      since then [eq_refl] is a valid proof of [m < n]. *)
  Definition mk' (m : N) {n : N} (prf : m < n) : fin.t n :=
    m ↾ prf.
  #[global] Arguments mk' m & {n} prf. (* [&] = infer [n] from return type. *)
  Notation mk m := (mk' m eq_refl).

  (** [weaken' x] notation converts [x : fin.t m] to [fin.t n] assuming [m <= n]. *)
  #[program] Definition weaken' {m n} (x : fin.t m) (prf : m <= n) : fin.t n :=
    fin.mk' (fin.to_N x) _.
  Next Obligation. move=> m n [/= ]; lia. Qed.
  #[global] Arguments weaken' {m} & {n} x prf. (* [&] = infer [n] from return type. *)

  (* Alternative:
  Notation weaken_alt x := (weaken' x ltac:(vm_decide)).
  Goal (weaken_alt (mk 10 : fin.t 11) : fin.t 42) = (mk 10 : fin.t 42).
  Proof. vm_decide. Abort.
  Goal (weaken_alt (mk 10 : fin.t 11) : fin.t 11) = (mk 10 : fin.t 11).
  Proof. vm_decide. Abort.
  ^ We avoid this alternative because [vm_decide]'s output is significantly larger.
  *)

  (** [weaken_bool_decide] is equivalent to [weaken'].
    But instead of [(m <= n)] we take [bool_decide (m <= n) = true], because
    that is provable by [eq_refl] when [m] and [n] are ground. *)
  #[program] Definition weaken_bool_decide {m n} (x : fin.t m)
      (prf : bool_decide (m <= n) = true) : fin.t n :=
    weaken' x _.
  Next Obligation. intros. exact: bool_decide_eq_true_1. Qed.
  #[global] Arguments weaken_bool_decide {m} & {n} x prf. (* [&] = infer [n] from return type. *)
  (** The [weaken x] notation converts [x : fin.t m] to [fin.t n].
      This assumes both [m] and [n] are ground, so that then [eq_refl] is a valid
      argument for [prf]. *)
  Notation weaken x := (weaken_bool_decide x eq_refl).

  Goal (weaken (mk 10 : fin.t 11) : fin.t 42) = (mk 10 : fin.t 42).
  Proof. vm_decide. Abort.
  Goal (weaken (mk 10 : fin.t 11) : fin.t 11) = (mk 10 : fin.t 11).
  Proof. vm_decide. Abort.

  (* [0; 1; 2 ... n - 1 ] *)
  Definition seq (n : N) : list (t n) :=
    match n with
    | N0 => []
    | Npos max => fin.of_N max <$> seqN 0 (Npos max)
    end.

  Lemma seq_lenN n : lengthN (seq n) = n.
  Proof. case: n => [//| p]. by rewrite fmap_lengthN seqN_lengthN. Qed.

  Lemma seq_len n : length (seq n) = N.to_nat n.
  Proof. by rewrite length_lengthN seq_lenN. Qed.

  Lemma seq_NoDup n : NoDup (seq n).
  Proof.
    apply NoDup_fmap_1 with (f := to_N).
    destruct n; [constructor | ].
    rewrite -list_fmap_compose (fmap_ext_in _ id) ?list_fmap_id.
    { apply NoDup_seqN. }
    move=> a /elem_of_seqN Hin /=.
    apply to_of_N. lia.
  Qed.

  Lemma elem_of_seq n {i : t n} : i ∈ seq n.
  Proof.
    destruct n. { by destruct t_0_inv. }
    apply elem_of_list_fmap; exists (to_N i); split.
    by rewrite of_to_N.
    apply elem_of_seqN. case: i =>/=. lia.
  Qed.

  #[global, refine] Instance t_finite n : Finite (t n) :=
    { enum := seq n; }.
  Proof. solve [apply seq_NoDup]. solve [apply elem_of_seq]. Defined.

  (** Conversion to and from the "indexed fin" type [fin] from the stdlib. *)
  #[program] Definition to_idx_fin' {m : N} (f : fin.t m) {n : nat} (_ : m = N.of_nat n) : fin n :=
    nat_to_fin (p := N.to_nat (fin.to_N f)) _.
  Next Obligation. move=> m [] /=. lia. Qed.
  #[global] Arguments to_idx_fin' {m} f & {n} prf. (* [&] = infer [n] from return type. *)
  Notation to_idx_fin x := (to_idx_fin' x eq_refl).

  #[program] Definition of_idx_fin' {m : nat} (f : fin m) {n : N} (_ : n = N.of_nat m) : fin.t n :=
    fin.mk' (N.of_nat (fin_to_nat f)) _.
  Next Obligation. move=> m f n ->. have := fin_to_nat_lt f. lia. Qed.
  #[global] Arguments of_idx_fin' {m} f & {n} prf. (* [&] = infer [n] from return type. *)
  Notation of_idx_fin x := (of_idx_fin' x eq_refl).

  Lemma of_to_idx_fin_cancel {m : N} {n : nat} (f : fin.t m) (E : m = N.of_nat n) :
    of_idx_fin' (to_idx_fin' f E) E = f.
  Proof. apply /t_eq. by rewrite /= fin_to_nat_to_fin N2Nat.id. Qed.

  Lemma to_of_idx_fin_cancel {m : N} {n : nat} (f : fin n) (E : m = N.of_nat n) :
    to_idx_fin' (of_idx_fin' f E) E = f.
  Proof.
    rewrite /to_idx_fin' /of_idx_fin' /= Fin.of_nat_ext {E} Nat2N.id.
    exact: fin_to_nat_lt.
    exact: nat_to_fin_to_nat.
  Qed.

  Definition decode `{Finite A} (f : fin.t (N.of_nat (card A))) : A :=
    decode_fin (to_idx_fin f).
  #[global] Arguments decode & {A _ _} f. (* [&] = infer [A] from return type. *)
End fin.
