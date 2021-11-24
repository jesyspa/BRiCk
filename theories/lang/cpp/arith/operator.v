(*
 * Copyright (c) 2020 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)

(**
 * Semantics of arithmetic and pointer operators: support operators.
 *)

From bedrock.prelude Require Import base numbers.
From bedrock.lang.cpp.arith Require Import types.

Local Open Scope Z_scope.

(** truncation (used for unsigned operations) *)
Definition trim (w : N) (v : Z) : Z :=
  v mod (2 ^ Z.of_N w).

Lemma trim_0_l:
  forall (v: Z),
    trim 0 v = 0.
Proof. move=> v; by rewrite /trim Z.pow_0_r Z.mod_1_r. Qed.

Lemma trim_0_r:
  forall (w: N),
    trim w 0 = 0.
Proof. move=> w; rewrite /trim Z.mod_0_l; [ | apply Z.pow_nonzero ]; lia. Qed.

Lemma trim_idem w v : trim w (trim w v) = trim w v.
Proof.
  rewrite /trim.
  by rewrite Zmod_mod.
Qed.

(** [to_unsigned sz z] is used when C++ converts signed values to unsigned
    values.

    "the unique value congruent to [z] modulo [2^sz]
     where [sz] is the number of bits in the return type"
 *)
Notation to_unsigned_bits := (trim) (only parsing).
Notation to_unsigned a    := (to_unsigned_bits (bitsN a)) (only parsing).

Definition bitFlipZU (len : bitsize) (z : Z) : Z :=
  to_unsigned len (Z.lnot z).

Lemma to_unsigned_bits_id : forall z (bits : N),
    0 <= z < 2 ^ (Z.of_N bits) ->
    to_unsigned_bits bits z = z.
Proof.
  rewrite /trim.
  intros. rewrite Z.mod_small; auto.
Qed.

Lemma to_unsigned_id : forall z (sz : bitsize),
    0 <= z < 2^bitsZ sz ->
    to_unsigned sz z = z.
Proof. destruct sz; apply to_unsigned_bits_id. Qed.

Lemma to_unsigned_bits_eq : forall z (bits: N),
    to_unsigned_bits bits z = trim bits z.
Proof. reflexivity. Qed.

Lemma to_unsigned_eq : forall z (sz : bitsize),
    to_unsigned sz z = trim (bitsN sz) z.
Proof. reflexivity. Qed.

(** [to_signed sz z] is used when C++ converts unsigned values to signed values.

    the standard describes it as:

    "the value does not change if the source integer can be represented in the
     destination type. Otherwise the result is,
     - implementation-defined (until C++20)
     - the unique value of the destination type equal to the source value modulo [2^sz]
       where [sz] is the number of bits used to represent the destination type."
 *)
Definition to_signed_bits (bits: N) (z: Z): Z :=
  if bool_decide (bits = 0%N)
  then 0
  else let norm := Z.modulo z (2 ^ (Z.of_N bits)) in
       if bool_decide (norm >= 2 ^ ((Z.of_N bits) - 1))
       then norm - 2 ^ (Z.of_N bits) else norm.
Definition to_signed (sz: bitsize) (z: Z): Z :=
  Unfold to_signed_bits (to_signed_bits (bitsN sz) z).

Local Transparent bitsZ bitsN.
Arguments bitsZ !_/.
Arguments Z.of_N !_/.
Arguments bitsN !_/.

(* lemmas for [to_signed] and [to_unsigned] *)
Lemma to_signed_bits_id: forall (z: Z) (bits: N),
    0 <= z < 2 ^ ((Z.of_N bits) - 1) -> to_signed_bits bits z = z.
Proof.
  intros ? ? [Hlower Hupper]; rewrite /to_signed_bits Z.mod_small; first last.
  - intuition; eapply Z.lt_trans; eauto;
      apply Z.pow_lt_mono_r; lia.
  - assert (bits = 0 \/ 0 < bits)%N as [Hbits | Hbits] by lia; subst.
    + rewrite Z.pow_neg_r in Hupper; lia.
    + rewrite bool_decide_eq_false_2; [ | by lia ].
      rewrite bool_decide_eq_false_2;
        by [| intro; contradiction].
Qed.

Lemma to_signed_id : forall (z : Z) (n : bitsize),
  0 <= z < 2^(bitsZ n - 1) -> to_signed n z = z.
Proof. destruct n; apply to_signed_bits_id. Qed.

Lemma to_signed_bits_neg: forall (z: Z) (bits: N),
    2^((Z.of_N bits) - 1) - 1 < z < 2^(Z.of_N bits) ->
    to_signed_bits bits z = trim bits (z - 2^((Z.of_N bits) - 1)) + - 2^((Z.of_N bits) - 1).
Proof.
  intros ? ? [Hlower Hupper]; rewrite /to_signed_bits /trim Z.mod_small; first last.
  - split; [ | by lia ].
    assert (Z.of_N bits - 1 < 0 \/ Z.of_N bits - 1 = 0 \/ 0 < Z.of_N bits - 1)%Z
      as [Hexp | [Hexp | Hexp]] by lia.
    + rewrite Z.pow_neg_r in Hlower; lia.
    + rewrite Hexp in Hlower; lia.
    + pose proof (Z.pow_pos_nonneg 2 (Z.of_N bits - 1) ltac:(lia) ltac:(lia)); lia.
  - assert (bits = 0 \/ 0 < bits)%N as [Hbits | Hbits] by lia; subst.
    + rewrite bool_decide_eq_true_2; last by [lia]; simpl in *.
      rewrite Z.mod_small; intuition lia.
    + rewrite bool_decide_eq_false_2; last by lia.
      rewrite bool_decide_eq_true_2 /=; last by [lia].
      rewrite Z.mod_small; (intuition auto with lia); first last.
      * eapply Z.lt_trans; eauto.
        assert (Z.of_N bits - 1 < 0 \/ Z.of_N bits - 1 = 0 \/ Z.of_N bits - 1 > 0)
          as [Hexp | [Hexp | Hexp]] by lia.
        -- rewrite Z.pow_neg_r; lia.
        -- rewrite Hexp; rewrite Z.pow_0_r; lia.
        -- pose proof (Z.pow_pos_nonneg 2 (Z.of_N bits - 1) ltac:(lia) ltac:(lia)); lia.
      * rewrite -{1}(Zplus_minus 1 (Z.of_N bits)) Z.add_1_l.
        rewrite Z.pow_succ_r; lia.
Qed.

Lemma to_signed_neg : forall x (n : bitsize),
    2^(bitsZ n - 1) - 1 < x < 2^bitsZ n ->
    to_signed n x = trim (bitsN n) (x - 2^(bitsZ n - 1)) + - 2^(bitsZ n - 1).
Proof. move=> x n H; by pose proof (to_signed_bits_neg x (bitsN n) H). Qed.

Lemma Z_opp1_mul_lt_ge:
  forall (n m: Z),
    (-n < m)%Z <->
    (-m < n)%Z.
Proof.
  split; intros.
  - rewrite -(Z.opp_involutive n) -Z.opp_lt_mono; lia.
  - rewrite -(Z.opp_involutive m) -Z.opp_lt_mono; lia.
Qed.

Lemma Zge_not_lt:
  forall (n m: Z),
    (n >= m)%Z -> not (n < m)%Z.
Proof. lia. Qed.

Lemma to_signed_unsigned_bits_roundtrip:
  forall (bits: N) (v: Z),
    (-2^(Z.of_N bits - 1) <= v)%Z ->
    (v <= 2^(Z.of_N bits - 1) - 1)%Z ->
    to_signed_bits bits (to_unsigned_bits bits v) = v.
Proof.
  intros bits v Hlower Hupper.
  assert (v < 0 \/ 0 = v \/ 0 < v)%Z as [Hv | [Hv | Hv]] by lia;
    [clear Hupper | subst; clear Hlower Hupper | clear Hlower].
  - rewrite /trim /to_signed_bits Zdiv.Zmod_mod.
    assert (bits = 0 \/ 0 < bits)%N as [Hbits | Hbits] by lia; subst.
    { rewrite bool_decide_eq_true_2 //;
        rewrite Z.pow_neg_r in Hlower; lia. }
    rewrite bool_decide_eq_false_2; last by [lia];
      match goal with
      | |- context[bool_decide ?P] =>
        destruct (bool_decide P) eqn:Heqb
      end=> //.
    + rewrite -(Z.opp_involutive v).
      rewrite Zdiv.Z_mod_nz_opp_full.
      { rewrite Zdiv.Zmod_small; intuition; try lia.
        rewrite Z_opp1_mul_lt_ge.
        eapply Z.lt_le_trans; eauto.
        rewrite -Z.opp_lt_mono.
        eapply Z.pow_lt_mono_r; lia. }
      rewrite Zdiv.Zmod_eq; first last.
      { rewrite Z.gt_lt_iff; apply Z.pow_pos_nonneg; lia. }
      rewrite Z.div_small; intuition; try lia.
      rewrite Z_opp1_mul_lt_ge.
      eapply Z.lt_le_trans; eauto.
      rewrite -Z.opp_lt_mono.
      eapply Z.pow_lt_mono_r; lia.
    + apply bool_decide_eq_false in Heqb.
      exfalso; apply Heqb; clear Heqb.
      replace (v) with (-(-v))%Z by lia.
      rewrite Zdiv.Z_mod_nz_opp_full; first last.
      { rewrite Zdiv.Zmod_small; intuition; try lia.
        rewrite Z_opp1_mul_lt_ge.
        eapply Z.lt_le_trans; eauto.
        rewrite -Z.opp_lt_mono.
        eapply Z.pow_lt_mono_r; lia. }
      rewrite Zdiv.Zmod_eq; first last.
      { rewrite Z.gt_lt_iff; apply Z.pow_pos_nonneg; lia. }
      rewrite Z.div_small; intuition; try lia; first last.
      { rewrite Z_opp1_mul_lt_ge.
        eapply Z.lt_le_trans; eauto.
        rewrite -Z.opp_lt_mono.
        eapply Z.pow_lt_mono_r; lia.
      }
      rewrite Z.mul_0_l Z.sub_0_r.
      rewrite Z.ge_le_iff.
      apply Zorder.Zle_0_minus_le.
      rewrite -Z.sub_add_distr.
      apply Zorder.Zle_minus_le_0.
      assert (-v <= 2^(Z.of_N bits - 1))%Z by lia.
      replace (2^Z.of_N bits)%Z with (2^(Z.of_N bits - 1) + 2^(Z.of_N bits - 1))%Z.
      2: {
        replace (Z.of_N bits)%Z with ((Z.of_N bits - 1) + 1)%Z
          at 3 by lia; rewrite Z.pow_add_r; lia.
      }
      by apply Zorder.Zplus_le_compat_r.
  - assert (bits = 0 \/ 0 < bits)%N as [Hbits | Hbits] by lia; subst.
    + rewrite trim_0_r /to_signed_bits bool_decide_eq_true_2; lia.
    + rewrite trim_0_r to_signed_bits_id; intuition eauto with lia.
      apply Z.pow_pos_nonneg; lia.
  - rewrite /trim /to_signed_bits Zdiv.Zmod_mod.
    assert (bits = 0 \/ 0 < bits)%N as [Hbits | Hbits] by lia; subst.
    { rewrite bool_decide_eq_true_2 //;
        rewrite Z.pow_neg_r in Hupper; lia. }
    rewrite bool_decide_eq_false_2; last by [lia];
      match goal with
      | |- context[bool_decide ?P] =>
        destruct (bool_decide P) eqn:Heqb
      end=> //.
    + apply bool_decide_eq_true in Heqb.
      rewrite Zdiv.Zmod_small in Heqb; intuition; try lia.
      eapply Z.le_lt_trans; eauto.
      match goal with
      | |- (_ < ?r)%Z => replace r with (r - 0)%Z by lia
      end.
      apply Z.sub_lt_le_mono; try apply Z.pow_lt_mono_r; lia.
    + apply Zdiv.Zmod_small; intuition; try lia.
      eapply Z.le_lt_trans; eauto.
      match goal with
      | |- (_ < ?r)%Z => replace r with (r - 0)%Z by lia
      end.
      apply Z.sub_lt_le_mono; try apply Z.pow_lt_mono_r; lia.
Qed.

Lemma to_signed_unsigned_roundtrip:
  forall (bits: bitsize) (v: Z),
    (-2^(Z.of_N (bitsN bits) - 1) <= v)%Z ->
    (v <= 2^(Z.of_N (bitsN bits) - 1) - 1)%Z ->
    to_signed bits (to_unsigned bits v) = v.
Proof.
  intros; apply (to_signed_unsigned_bits_roundtrip (bitsN bits));
    destruct bits; simpl in *; lia.
Qed.

Local Lemma pow2Nm1gt1 {n : N} :
  (0 < n)%N -> 1 <= 2^(Z.of_N n - 1).
Proof.
  intros Hgt0.
  change 1%Z with (2^0)%Z.
  apply Z.pow_le_mono_r; lia.
Qed.

Lemma trim_to_signed_bits_agree x n :
  trim n (to_signed_bits n x) = trim n x.
Proof.
  assert (n = 0 \/ 0 < n)%N as [-> | Hn] by lia.
  - by rewrite /trim /to_signed_bits /= Z.pow_0_r !Z.mod_1_r.
  - have Hgt : 2 ^ Z.of_N n > 0 by apply Z.gt_lt_iff, Z.pow_pos_nonneg; lia.
    have Hge : 2 ^ Z.of_N n ≠ 0 by lia.
    have Hgt' := pow2Nm1gt1 Hn.
    have Hrng := Zdiv.Z_mod_lt x (2^Z.of_N n) Hgt.
    rewrite /trim /to_signed_bits bool_decide_eq_false_2; last by lia.
    case_bool_decide as Hdec; simpl; last by [rewrite Z.mod_mod].
    rewrite -Z.mod_opp_r_nz; try lia.
    rewrite -{1}(Z.opp_involutive x).
    rewrite Z.mod_opp_opp //.
    rewrite (Zdiv.Z_mod_nz_opp_full (_ mod _)) Z.mod_mod //
      Zdiv.Z_mod_nz_opp_full; lia.
Qed.

Lemma trim_to_signed_agree: forall x sz n,
    bitsN sz = n ->
    trim n (to_signed sz x) = trim n x.
Proof.
  move=> x sz n Hsz; subst.
  by rewrite -(trim_to_signed_bits_agree x (bitsN sz)).
Qed.
