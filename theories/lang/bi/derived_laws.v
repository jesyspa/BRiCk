(*
 * Copyright (c) 2020-2022 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)
(** *)

From iris.bi Require Import bi lib.fractional.
From iris.proofmode Require Import proofmode.
From bedrock.lang.bi Require Import only_provable.

(**
Derived BI laws, similarly to iris.bi.derived_laws.

They should be upstreamed if appropriate.
When upstreaming, add a comment (with the upstream name if different).
When bumping Iris, drop lemmas that are now upstream.
*)

Module bi.
Export iris.bi.bi.bi.

Section derived_laws.
  Context {PROP : bi}.

  Lemma affinely_pure φ  : <affine> ⌜φ⌝ ⊣⊢@{PROP} [| φ |].
  Proof. done. Qed.

  Lemma intuitionistically_pure φ  : □ ⌜φ⌝ ⊣⊢@{PROP} [| φ |].
  Proof.
    by rewrite /bi_intuitionistically bi.persistently_pure affinely_pure.
  Qed.

  Lemma exist_pure_eq_sep {A P} v:
    P v ⊢@{PROP} ∃ x : A, ⌜ x = v ⌝ ∗ P x.
  Proof. iIntros. iExists v; eauto. Qed.

  Lemma exist_and_exist {A B P Q} :
    (∃ (a : A), P a ∧ ∃ (b : B), Q a b) ⊣⊢@{PROP} ∃ b a, P a ∧ Q a b.
  Proof. rewrite exist_exist; f_equiv => a. apply bi.and_exist_l. Qed.

  (* Provided just for uniformity with [and_exist_and_r]. *)
  Lemma and_exist_and_l {A P Q R} :
     P ∧ (∃ a : A, Q a ∧ R a) ⊣⊢@{PROP} (∃ a : A, P ∧ Q a ∧ R a).
  Proof. apply bi.and_exist_l. Qed.

  Lemma and_exist_and_r {A P Q R} :
    (∃ a : A, P a ∧ Q a) ∧ R ⊣⊢@{PROP} (∃ a : A, P a ∧ Q a ∧ R).
  Proof. rewrite bi.and_exist_r; f_equiv=> a. by rewrite -assoc. Qed.

  (** Useful when proving Fractional instances involving existentials. *)
  Lemma exist_sep_1 {A} (Φ Ψ : A → PROP) : (∃ a, Φ a ∗ Ψ a) ⊢ (∃ a, Φ a) ∗ (∃ a, Ψ a).
  Proof.
    rewrite bi.sep_exist_r. f_equiv=>a. f_equiv.
    apply bi.exist_intro.
  Qed.

  Lemma exist_sep_2 {A} (Φ Ψ : A → PROP) :
    (∀ a1 a2, Φ a1 ⊢ Ψ a2 -∗ ⌜a1 = a2⌝) →
    (∃ a, Φ a) ∗ (∃ a, Ψ a) ⊢ (∃ a, Φ a ∗ Ψ a).
  Proof.
    iIntros (Hag) "[A1 A2]".
    iDestruct "A1" as (a1) "Φ".
    iDestruct "A2" as (a2) "Ψ".
    iDestruct (Hag with "Φ Ψ") as %->.
    iExists a2; iFrame.
  Qed.

  Lemma exist_sep {A} (Φ Ψ : A → PROP)
    (Hag : ∀ a1 a2, Φ a1 ⊢ Ψ a2 -∗ ⌜a1 = a2⌝) :
    (∃ a, Φ a ∗ Ψ a) ⊣⊢ (∃ a, Φ a) ∗ (∃ a, Ψ a).
  Proof. apply (anti_symm (⊢)); eauto using exist_sep_1, exist_sep_2. Qed.

  Lemma exist_and_1 {A} (Φ Ψ : A → PROP) : (∃ a, Φ a ∧ Ψ a) ⊢ (∃ a, Φ a) ∧ (∃ a, Ψ a).
  Proof.
    rewrite bi.and_exist_r. f_equiv=>a. f_equiv.
    apply bi.exist_intro.
  Qed.

  Lemma exist_and_2 {A} (Φ Ψ : A → PROP)
    (Hag : ∀ a1 a2, Φ a1 ∧ Ψ a2 ⊢ ⌜a1 = a2⌝) :
    (∃ a, Φ a) ∧ (∃ a, Ψ a) ⊢ (∃ a, Φ a ∧ Ψ a).
  Proof.
    rewrite bi.and_exist_l. f_equiv=> a1.
    rewrite bi.and_exist_r.
    iDestruct 1 as (a2) "H".
    iSplit; last by iDestruct "H" as "[_ $]".
    by iDestruct (Hag with "[H]") as %->; last iDestruct "H" as "[$ _]".
  Qed.

  Lemma exist_and {A} (Φ Ψ : A → PROP)
    (Hag : ∀ a1 a2, Φ a1 ∧ Ψ a2 ⊢ ⌜a1 = a2⌝) :
    (∃ a, Φ a ∧ Ψ a) ⊣⊢ (∃ a, Φ a) ∧ (∃ a, Ψ a).
  Proof. apply (anti_symm (⊢)); eauto using exist_and_1, exist_and_2. Qed.

  Lemma forall_sep_bot {A} (Φ1 Φ2 : A → PROP) (R : relation A) (bot : A) :
    (∀ x, R bot x) → Proper (R ==> (⊢)) Φ1 → Proper (R ==> (⊢)) Φ2 →
    (∀ a, Φ1 a ∗ Φ2 a) ⊢ (∀ a, Φ1 a) ∗ (∀ a, Φ2 a).
  Proof.
    intros. rewrite (forall_elim bot). f_equiv; auto using forall_intro.
  Qed.

  Lemma and_forall {A} (P Q : A -> PROP) :
    (∀ x : A, P x) ∧ (∀ x : A, Q x) ⊣⊢ (∀ x : A, P x ∧ Q x).
  Proof.
    apply (anti_symm _).
    { apply forall_intro => a. apply and_intro;
        (etrans; last apply forall_elim);
        trivial using and_elim_l, and_elim_r. }
    { apply and_intro; apply forall_intro => x;
        (etrans; last apply forall_elim); apply forall_mono=>{}x;
        trivial using and_elim_l, and_elim_r. }
  Qed.

  Lemma and_wand_distr_l (P Q R : PROP) :
    (P -∗ Q) ∧ (P -∗ R) ⊣⊢ (P -∗ (Q ∧ R)).
  Proof.
    apply (anti_symm _).
    { apply wand_intro_r, and_intro;
        (etrans; last apply (wand_elim_l P)); f_equiv;
        trivial using and_elim_l, and_elim_r. }
    { apply and_intro; f_equiv; trivial using and_elim_l, and_elim_r. }
  Qed.

  Lemma wand_wand_swap (P Q R : PROP) :
    (P -∗ Q -∗ R) -> (Q -∗ P -∗ R).
  Proof. intros HW. apply wand_intro_l, wand_elim_l', HW. Qed.

  Lemma and_wand_distr_r (P Q R : PROP) :
    (P -∗ R) ∧ (Q -∗ R) ⊣⊢ (P ∨ Q -∗ R).
  Proof.
    apply (anti_symm _).
    { apply wand_wand_swap, or_elim; apply wand_wand_swap; trivial using and_elim_l, and_elim_r. }
    { apply and_intro; apply wand_mono; trivial using or_intro_l, or_intro_r. }
  Qed.

  (** Lemmas about modalities. *)

  Lemma forall_affinely_bot {A} (Φ : A → PROP) (R : relation A) (bot : A) :
    (∀ x, R bot x) → Proper (R ==> (⊢)) Φ →
    (∀ a, <affine> (Φ a)) ⊢ <affine> (∀ a, Φ a).
  Proof.
    intros. rewrite (forall_elim bot). f_equiv. auto using forall_intro.
  Qed.

  Lemma forall_intuitionistically_bot `{!BiPersistentlyForall PROP}
      {A} (Φ : A → PROP) (R : relation A) (bot : A) :
    (∀ x, R bot x) → Proper (R ==> (⊢)) Φ →
    (∀ a, □ (Φ a)) ⊢ □ (∀ a, Φ a).
  Proof.
    intros Hbot ?. rewrite /bi_intuitionistically.
    rewrite persistently_forall. apply (forall_affinely_bot _ _ _ Hbot).
    solve_proper.
  Qed.

  Lemma intuitionistically_if_forall b {A} (Φ : A → PROP) :
    □?b (∀ x : A, Φ x) -∗ ∀ x : A, □?b Φ x.
  Proof.
    destruct b; [|done]. apply intuitionistically_forall.
  Qed.
  Lemma forall_intuitionistically_if_bot `{!BiPersistentlyForall PROP}
      b {A} (Φ : A → PROP) (R : relation A) (bot : A) :
    (∀ x, R bot x) → Proper (R ==> (⊢)) Φ →
    (∀ a, □?b (Φ a)) ⊢ □?b (∀ a, Φ a).
  Proof.
    intros. destruct b; [|done]. exact: forall_intuitionistically_bot.
  Qed.

  Lemma intuitionistically_and_sep P Q : □ (P ∧ Q) ⊣⊢@{PROP} □ P ∗ □ Q.
  Proof.
    by rewrite bi.intuitionistically_and bi.and_sep_intuitionistically.
  Qed.

  Lemma persistent_sep_distr_l (P Q R : PROP) `{!Persistent P, !Affine P} :
    P ∗ Q ∗ R ⊣⊢ (P ∗ Q) ∗ (P ∗ R).
  Proof.
    rewrite {1}(persistent_sep_dup P).
    iSplit; iIntros "[[$$] [$$]]".
  Qed.

  Lemma persistent_sep_distr_r (P Q R : PROP) `{!Persistent R, !Affine R} :
    (P ∗ Q) ∗ R ⊣⊢ (P ∗ R) ∗ (Q ∗ R).
  Proof. rewrite !(comm bi_sep _ R). exact: persistent_sep_distr_l. Qed.

  Lemma persistent_sep_and_distr_l P Q1 Q2 `{!Persistent P} `{!Affine P} :
    P ∗ (Q1 ∧ Q2) ⊣⊢@{PROP}
    (P ∗ Q1) ∧ (P ∗ Q2).
  Proof.
    iSplit. by iIntros "[$ $]".
    iIntros "H"; iSplit. by iDestruct "H" as "[[$ _] _]".
    iSplit.
    iDestruct "H" as "[[_ $]_]".
    iDestruct "H" as "[_ [_ $]]".
  Qed.

  Lemma persistent_sep_and_distr_r {P1 P2 Q} `{!Persistent Q} `{!Affine Q} :
    (P1 ∧ P2) ∗ Q ⊣⊢@{PROP}
    (P1 ∗ Q) ∧ (P2 ∗ Q).
  Proof. rewrite !(comm bi_sep _ Q). exact: persistent_sep_and_distr_l. Qed.
End derived_laws.

Section only_provable_derived_laws.
  Context {PROP : bi}.

  Lemma exist_only_provable_eq_sep {A P} v:
    P v ⊢@{PROP} ∃ x : A, [| x = v |] ∗ P x.
  Proof. iIntros. iExists v; eauto. Qed.

  Lemma exist_sep_only_provable {A} (Φ Ψ : A → PROP)
    (Hag : ∀ a1 a2, Φ a1 ⊢ Ψ a2 -∗ [| a1 = a2 |]) :
    (∃ a, Φ a ∗ Ψ a) ⊣⊢ (∃ a, Φ a) ∗ (∃ a, Ψ a).
  Proof.
    apply exist_sep.
    iIntros (??) "Q R". by iDestruct (Hag with "Q R") as %->.
  Qed.

  Lemma exist_and_only_provable {A} (Φ Ψ : A → PROP)
    (Hag : ∀ a1 a2, Φ a1 ∧ Ψ a2 ⊢ [| a1 = a2 |]) :
    (∃ a, Φ a ∧ Ψ a) ⊣⊢ (∃ a, Φ a) ∧ (∃ a, Ψ a).
  Proof.
    apply exist_and.
    iIntros (??) "Q". by iDestruct (Hag with "Q") as %->.
  Qed.

  Lemma exist_and_agree {A : Type} (Θ Φ Ψ : A → PROP)
      `{∀ a, Affine (Θ a), ∀ a, Persistent (Θ a)}
    (Hagree : ∀ a1 a2, Θ a1 ∗ Θ a2 ⊢ [| a1 = a2 |]) :
    (∃ a, Θ a ∗ (Φ a ∧ Ψ a)) ⊣⊢ (∃ a, Θ a ∗ Φ a) ∧ (∃ a, Θ a ∗ Ψ a).
  Proof.
    apply (anti_symm _).
    - rewrite -exist_and_1. f_equiv=>a. iDestruct 1 as "[$ $]".
    - rewrite and_exist_l. f_equiv=> a2. iIntros "H".
      iAssert (Θ a2) as "#Ha"; first by iDestruct "H" as "[_ [$ _]]".
      iFrame "Ha". iSplit; last by iDestruct "H" as "[_ [_ $]]".
      rewrite and_exist_r. iDestruct "H" as (a1) "[[Ha2 R] _]".
      by iDestruct (Hagree a1 a2 with "[$Ha2]") as "->".
  Qed.

  Lemma exist_sep_agree {A : Type} (Θ Φ Ψ : A → PROP)
      `{∀ a, Affine (Θ a), ∀ a, Persistent (Θ a)}
    (Hagree : ∀ a1 a2, Θ a1 ∗ Θ a2 ⊢ [| a1 = a2 |]) :
    (∃ a, Θ a ∗ (Φ a ∗ Ψ a)) ⊣⊢ (∃ a, Θ a ∗ Φ a) ∗ (∃ a, Θ a ∗ Ψ a).
  Proof.
    rewrite -exist_sep //.
    - f_equiv => a. exact: persistent_sep_distr_l.
    - iIntros (??) "[A _] [B _]".
      by iDestruct (Hagree with "[$A $B]") as %->.
  Qed.
End only_provable_derived_laws.

Section embed_derived_laws.
  Context `{BiEmbed PROP1 PROP2}.
  Local Notation embed := (embed (A:=PROP1) (B:=PROP2)).

  Global Instance embed_fractional (P : Qp → PROP1) :
    Fractional P → Fractional (λ q, embed (P q)).
  Proof. intros ???. by rewrite -embed_sep fractional. Qed.
End embed_derived_laws.
End bi.
