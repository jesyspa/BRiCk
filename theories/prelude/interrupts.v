(*
 * Copyright (C) 2020 BedRock Systems, Inc.
 * All rights reserved.
 *
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 *)

(* XXX Only temporarily here. *)

From bedrock.prelude Require Import base hw_types.

(** * Configurations of the interrupt lines attached to devices *)

Variant IntTrigger :=
| TriggerEdge
  (* ^ int is edge triggered *)
| TriggerLevel (active_low : bool).
  (* ^ int is low-level triggered [active_low = true]; otherwise, high-level triggered *)

#[global] Instance int_trigger_inhabited : Inhabited IntTrigger.
Proof. solve_inhabited. Qed.
#[global] Instance int_trigger_decision : EqDecision IntTrigger.
Proof. solve_decision. Defined.

Variant IntOwner :=
| HostInt
(* ^ int is host owned *)
| GuestInt.
(* ^ int is guest owned (VM passthrough) *)

#[global] Instance int_owner_inhabited : Inhabited IntOwner.
Proof. solve_inhabited. Qed.
#[global] Instance int_owner_decision : EqDecision IntOwner.
Proof. solve_decision. Defined.

Variant IntStatus : Set := IntMasked | IntEnabled.

#[global] Instance int_status_inhabited : Inhabited IntStatus.
Proof. solve_inhabited. Qed.
#[global] Instance int_status_decision : EqDecision IntStatus.
Proof. solve_decision. Defined.

Record IntConfig : Set :=
  { int_cpu : option cpu
  ; int_trigger : option IntTrigger
  ; int_owner : option IntOwner
  ; int_status : IntStatus }.

(* The IntConfig value before the first assign_int *)
Definition initialIntConfig :=
  {| int_cpu := None
  ;  int_trigger := None
  ;  int_owner := None
  ;  int_status := IntMasked
  |}.

#[global] Instance int_config_inhabited : Inhabited IntConfig.
Proof. solve_inhabited. Qed.
#[global] Instance int_cfg_decision : EqDecision IntConfig.
Proof. solve_decision. Defined.

(** [intline_of (x : T)]: The interrupt line attached to some value [x : T] *)
Class IntLines (T : Type) := intline_of : T -> int_line.
#[global] Hint Mode IntLines + : typeclass_instances.

(** * Interrupt signals generated by devices *)

Variant InterruptSignal : Set :=
| LevelSig (_ : bool)
| EdgeSig.
  (* ^ note(gmm): it might not be possible to implement [EdgeSig] as successive
   * [LevelSig true, LevelSig false] because arbitrary scheduling can occur between
   * two events, so the [LevelSig true] might hide other interrupts.
   *)

#[global] Instance InterruptSignal_inhabited : Inhabited InterruptSignal.
Proof. solve_inhabited. Qed.
#[global] Instance InterruptSignal_eq_dec : EqDecision InterruptSignal.
Proof. solve_decision. Defined.

Definition int_types_match (sig : InterruptSignal) (ty : IntConfig) : Prop :=
  match sig with
  | LevelSig high => ty.(int_trigger) = Some $ TriggerLevel (negb high)
    (* ^ [high = true] is a valid level trigger only if
         [TriggerLevel false (*= active_low*)]. *)
  | EdgeSig => ty.(int_trigger) = Some TriggerEdge
  end.

#[global] Instance int_types_match_decision sig cfg : Decision (int_types_match sig cfg).
Proof. case: cfg => ?; case: sig => /=; by apply: _. Defined.

(** [intcfg_valid cfg own sig] means that [cfg] matches [sig], the interrupt line was
    configured [IntEnabled], and the owner is [own] (guest or host). *)
Definition intcfg_valid (cfg : IntConfig) (own : IntOwner) (sig : InterruptSignal) : Prop :=
    int_types_match sig cfg /\
    cfg.(int_owner) = Some own /\
    cfg.(int_status) = IntEnabled.

(* Confirm these instances are already derivable. *)
#[global] Instance intline_elem_of_dec :
  @RelDecision (int_line * IntConfig) (list (int_line * IntConfig)) elem_of.
Proof. apply _. Abort.

#[global] Instance intcfg_valid_decision cfg own sig : Decision (intcfg_valid cfg own sig).
Proof. apply _. Abort.

Record IntAction :=
{ line : int_line
; to : InterruptSignal
}.

#[global] Instance IntAction_inhabited : Inhabited IntAction.
Proof. solve_inhabited. Defined.
#[global] Instance IntAction_eq_dec : EqDecision IntAction.
Proof. solve_decision. Defined.
