Require Import Coq.ZArith.ZArith.
Require Import compiler.FlatImp.
Require Import coqutil.Decidable.
Require Import Coq.Lists.List. Import ListNotations.
Require Import riscv.Utility.Utility.
Require Import coqutil.Macros.unique.
Require Import coqutil.Map.Interface.
Require Import coqutil.Map.Properties.
Require Import coqutil.Map.Solver.
Require Import coqutil.Tactics.Tactics.
Require Import coqutil.Map.TestLemmas.
Require Import bedrock2.Syntax.
Require Import compiler.util.ListLib.
Require Import compiler.Simp.
Require Import compiler.Simulation.


Local Notation "'bind_opt' x <- a ; f" :=
  (match a with
   | Some x => f
   | None => None
   end)
  (right associativity, at level 70, x pattern).

Axiom TODO_sam: False.

Module map.
  Definition putmany_of_pairs{K V: Type}{M: map.map K V}(m: M): list (K * V) -> M :=
    fix rec l :=
    match l with
    | nil => m
    | (k, v) :: rest => map.put (rec rest) k v
    end.

  Lemma putmany_of_pairs_extends{K V: Type}{M: map.map K V}{ok: map.ok M}
        {key_eqb: K -> K -> bool}{key_eq_dec: EqDecider key_eqb}:
    forall (pairs: list (K * V)) (m1 m2: M),
    map.extends m1 m2 ->
    map.extends (putmany_of_pairs m1 pairs) (putmany_of_pairs m2 pairs).
  Proof.
    induction pairs; intros.
    - simpl. assumption.
    - simpl. destruct a as [k v]. apply map.put_extends. eapply IHpairs. assumption.
  Qed.
End map.

Section RegAlloc.

  Context {srcvar: Type}.
  Context (srcvar_eqb: srcvar -> srcvar -> bool).
  Context {impvar: Type}.
  Context (impvar_eqb: impvar -> impvar -> bool).
  Context {func: Type}.
  Context (func_eqb: func -> func -> bool).
  Context {act: Type}.
  Context (act_eqb: act -> act -> bool).

  Context {srcvar_eq_dec : EqDecider srcvar_eqb}.
  Context {impvar_eq_dec : EqDecider impvar_eqb}.

  Context {src2imp: map.map srcvar impvar}.
  Context {src2impOk: map.ok src2imp}.

  Instance srcparams: Syntax.parameters := {|
    Syntax.varname := srcvar;
    Syntax.funname := func;
    Syntax.actname := act;
  |}.

  Instance impparams: Syntax.parameters := {|
    Syntax.varname := impvar;
    Syntax.funname := func;
    Syntax.actname := act;
  |}.

  Local Notation stmt  := (@FlatImp.stmt srcparams). (* input type *)
  Local Notation stmt' := (@FlatImp.stmt impparams). (* output type *)

  Variable available_impvars: list impvar.

  Definition rename_assignment_lhs(m: src2imp)(x: srcvar)(a: list impvar):
    option (src2imp * impvar * list impvar) :=
    match map.get m x with
    | Some y => Some (m, y, a)
    | None   => match a with
                | y :: rest => Some (map.put m x y, y, rest)
                | nil => None
                end
    end.

  Definition rename_assignment_rhs(m: src2imp)(s: stmt)(y: impvar): option stmt' :=
    match s with
    | SLoad sz x a => bind_opt a' <- map.get m a; Some (SLoad sz y a')
    | SLit x v => Some (SLit y v)
    | SOp x op a b => bind_opt a' <- map.get m a; bind_opt b' <- map.get m b;
                      Some (SOp y op a' b')
    | SSet x a => bind_opt a' <- map.get m a; Some (SSet y a')
    | _ => None
    end.

  Fixpoint rename_binds(m: src2imp)(binds: list srcvar)(a: list impvar):
    option (src2imp * list (srcvar * impvar) * list impvar) :=
    match binds with
    | nil => Some (m, nil, a)
    | x :: binds =>
      bind_opt (m, y, a) <- rename_assignment_lhs m x a;
      bind_opt (m, res, a) <- rename_binds m binds a;
      Some (m, (x, y) :: res, a)
    end.

  Definition rename_cond(m: src2imp)(cond: @bcond srcparams): option (@bcond impparams) :=
    match cond with
    | CondBinary op x y => bind_opt x' <- map.get m x;
                           bind_opt y' <- map.get m y;
                           Some (CondBinary op x' y')
    | CondNez x => bind_opt x' <- map.get m x; Some (CondNez x')
    end.

  (* The simplest dumbest possible "register allocator": Just renames, according to
     a global mapping m being constructed as we go.
     Returns None if not enough registers. *)
  Fixpoint rename
           (m: src2imp)              (* current mapping, growing *)
           (s: stmt)                 (* current sub-statement *)
           (a: list impvar)          (* available registers, shrinking *)
           {struct s}
    : option (src2imp * stmt' * list impvar) :=
    match s with
    | SLoad _ x _ | SLit x _ | SOp x _ _ _ | SSet x _ =>
      bind_opt (m', y, a) <- rename_assignment_lhs m x a;
      bind_opt s' <- rename_assignment_rhs m s y;
      Some (m', s', a)
    | SStore sz x y =>
      bind_opt x' <- map.get m x;
      bind_opt y' <- map.get m y;
      Some (m, SStore sz x' y', a)
    | SIf cond s1 s2 =>
      bind_opt (m', s1', a') <- rename m s1 a;
      bind_opt (m'', s2', a'') <- rename m' s2 a';
      bind_opt cond' <- rename_cond m cond;
      Some (m'', SIf cond' s1' s2', a'')
    | SSeq s1 s2 =>
      bind_opt (m', s1', a') <- rename m s1 a;
      bind_opt (m'', s2', a'') <- rename m' s2 a';
      Some (m'', SSeq s1' s2', a'')
    | SLoop s1 cond s2 =>
      bind_opt (m', s1', a') <- rename m s1 a;
      bind_opt cond' <- rename_cond m' cond;
      bind_opt (m'', s2', a'') <- rename m' s2 a';
      Some (m'', SLoop s1' cond' s2', a'')
    | SCall binds f args =>
      bind_opt (m, tuples, a) <- rename_binds m binds a;
      bind_opt args' <- map.getmany_of_list m args;
      Some (map.putmany_of_pairs m tuples, SCall (List.map snd tuples) f args', a)
    | SInteract binds f args =>
      bind_opt (m, tuples, a) <- rename_binds m binds a;
      bind_opt args' <- map.getmany_of_list m args;
      Some (map.putmany_of_pairs m tuples, SInteract (List.map snd tuples) f args', a)
    | SSkip => Some (m, SSkip, a)
    end.

  Definition rename_stmt(m: src2imp)(s: stmt)(av: list impvar): stmt' :=
    match rename m s av with
    | Some (_, s', _) => s'
    | None => SSkip
    end.

  Definition rename_fun(F: list srcvar * list srcvar * stmt):
    option (list impvar * list impvar * stmt') :=
    let '(argnames, retnames, body) := F in
    bind_opt (m, argtuples, av) <- rename_binds map.empty argnames available_impvars;
    bind_opt (m, rettuples, av) <- rename_binds m retnames av;
    bind_opt (_, body', _) <- rename m body av;
    Some (List.map snd argtuples, List.map snd rettuples, body').

  Context {W: Utility.Words} {mem: map.map word byte}.
  Context {srcLocals: map.map srcvar word}.
  Context {impLocals: map.map impvar word}.
  Context {srcLocalsOk: map.ok srcLocals}.
  Context {impLocalsOk: map.ok impLocals}.
  Context {funname_env: forall T: Type, map.map func T}.
  Context (ext_spec:  list (mem * actname * list word * (mem * list word)) ->
                      mem -> actname -> list word -> (mem -> list word -> Prop) -> Prop).

  Instance srcSemanticsParams: Semantics.parameters. refine ({|
    Semantics.syntax := srcparams;
    Semantics.varname_eqb := srcvar_eqb;
    Semantics.funname_eqb := func_eqb;
    Semantics.actname_eqb := act_eqb;
    Semantics.locals := srcLocals;
    Semantics.ext_spec := ext_spec;
  |}).
  Defined.

  Instance impSemanticsParams: Semantics.parameters. refine ({|
    Semantics.syntax := impparams;
    Semantics.varname_eqb := impvar_eqb;
    Semantics.funname_eqb := func_eqb;
    Semantics.actname_eqb := act_eqb;
    Semantics.locals := impLocals;
    Semantics.ext_spec := ext_spec;
  |}).
  Defined.

  Definition rename_function(e: @FlatImp.env srcSemanticsParams)(f: funname):
    (list impvar * list impvar * stmt') :=
    match map.get e f with
    | Some F => match rename_fun F with
                | Some res => res
                | None => (nil, nil, FlatImp.SSkip)
                end
    | None => (nil, nil, FlatImp.SSkip)
    end.

  Definition rename_functions(e: @FlatImp.env srcSemanticsParams):
    list funname -> @FlatImp.env impSemanticsParams :=
    fix rec funs :=
      match funs with
      | f :: rest => map.put (rec rest) f (rename_function e f)
      | nil => map.empty
      end.

  Definition states_compat(lH: srcLocals)(m: src2imp)(lL: impLocals) :=
    forall (x: srcvar) (y: impvar),
      map.get m x = Some y ->
      map.get lH x = map.get lL y.

  Lemma getmany_of_list_states_compat: forall srcnames impnames r lH lL argvals,
      map.getmany_of_list lH srcnames = Some argvals ->
      map.getmany_of_list r srcnames = Some impnames ->
      states_compat lH r lL ->
      map.getmany_of_list lL impnames = Some argvals.
  Proof.
    induction srcnames; intros;
      destruct argvals as [|argval argvals];
      destruct impnames as [|impname impnames];
      try reflexivity;
      try discriminate;
      unfold map.getmany_of_list, List.option_all in *; simpl in *;
        repeat (destruct_one_match_hyp; try discriminate).
    simp.
    replace (map.get lL impname) with (Some argval); cycle 1. {
      rewrite <- E1.
      unfold states_compat in *; eauto.
    }
    erewrite IHsrcnames; eauto.
  Qed.

  Ltac head e :=
    match e with
    | ?a _ => head a
    | _ => e
    end.

  Definition envs_related(e1: @env srcSemanticsParams)
                         (e2: @env impSemanticsParams): Prop :=
    forall f impl1,
      map.get e1 f = Some impl1 ->
      exists impl2,
        rename_fun impl1 = Some impl2.

  Lemma rename_assignment_lhs_get{r x av r' i av'}:
    rename_assignment_lhs r x av = Some (r', i, av') ->
    map.get r' x = Some i.
  Proof.
    intros.
    unfold rename_assignment_lhs in *.
    destruct_one_match_hyp; try congruence.
    destruct_one_match_hyp; try congruence.
    simp.
    apply map.get_put_same.
  Qed.

  Lemma state_compat_put: forall lH lL r x av r' y av' v,
      rename_assignment_lhs r x av = Some (r', y, av') ->
      states_compat lH r lL ->
      states_compat (map.put lH x v) r' (map.put lL y v).
  Proof.
    unfold rename_assignment_lhs, states_compat. intros.
    destruct (map.get r x); simp.
    - specialize H0 with (1 := H1).
      do 2 rewrite map.get_put_dec.
      (* needs injectivity of r *)
  Abort.

  Lemma checker_correct: forall eH eL,
      envs_related eH eL ->
      forall sH t m lH mc post,
      @exec srcSemanticsParams eH sH t m lH mc post ->
      forall lL r r' av av' sL,
      rename r sH av = Some (r', sL, av') ->
      states_compat lH r lL ->
      @exec impSemanticsParams eL sL t m lL mc (fun t' m' lL' mc' =>
        exists lH', states_compat lH' r' lL' /\
                    post t' m' lH' mc').
  Proof.
    (*
    intros.
    destruct H0 eqn: E;
    match type of E with
    | _ = ?r => let h := head r in idtac "- (*" h "*)"
    end.
    *)
    induction 2; intros; simpl in *; simp.

    - (* @exec.interact *)
      case TODO_sam.
    - (* @exec.call *)
      case TODO_sam.
    - (* @exec.load *)
      case TODO_sam.
    - (* @exec.store *)
      case TODO_sam.
    - (* @exec.lit *)
      case TODO_sam.
    - (* @exec.op *)
      rename l into lH.
      pose proof (rename_assignment_lhs_get E) as P.
      unfold states_compat in *|-.
      econstructor.
      + erewrite <- H4; cycle 1; eassumption.
      + erewrite <- H4; cycle 1; eassumption.
      + exists (map.put lH x (Semantics.interp_binop op y' z')).
        split.
        * intros. case TODO_sam.
        * case TODO_sam.
    - (* @exec.set *)
      case TODO_sam.
    - (* @exec.if_true *)
      case TODO_sam.
    - (* @exec.if_false *)
      case TODO_sam.
    - (* @exec.loop *)
      case TODO_sam.
    - (* @exec.seq *)
      rename IHexec into IH1, H2 into IH2.
      econstructor.
      1: eapply IH1; eassumption.
      cbv beta.
      intros. simp.
      eapply IH2; eassumption.
    - (* @exec.skip *)
      case TODO_sam.
  Qed.



(*
unfold states_compat, rename_assignment_lhs in *;


  Lemma states_compat_put: forall lH lL v x y r,
      map.get r x = None ->
      states_compat lH r lL ->
      states_compat (map.put lH x v) (map.put r x y) (map.put lL y v).
  Proof.
    unfold states_compat.
    intros.
    rewrite (map.get_put_dec (key_eqb := impvar_eqb)).
    lazymatch goal with
    | H: map.get (map.put _ _ _) _ = _ |- _ => rewrite map.get_put_dec in H
    end.
    lazymatch goal with
    | H: gett (putt _ _ _) _ = _ |- _ => rewrite gett_putt_dec in H
    end.
    destruct_one_match_hyp.
    - subst x0. replace y0 with y by congruence. replace w with v by congruence.
      destruct_one_match; congruence.
    - specialize H0 with (1 := H1) (2 := H2).
*)

  Lemma putmany_of_list_states_compat: forall binds resvals lL lH lH' r,
      map.putmany_of_list (map fst binds) resvals lH = Some lH' ->
      states_compat lH r lL ->
      exists lL',
        map.putmany_of_list (map snd binds) resvals lL = Some lL' /\
        states_compat lH' (map.putmany_of_pairs r binds) lL'.
  Proof.
    induction binds; intros.
    - simpl in H. simp. simpl. eauto.
    - simpl in *. simp.
      specialize IHbinds with (1 := H).
      destruct a as [sv iv].
      apply map.putmany_of_list_sameLength in H.
      rewrite map_length in H. rewrite <- (map_length snd) in H.
      eapply map.sameLength_putmany_of_list in H.
      destruct H as (lL' & H).
      exists lL'. split; [exact H|].
  Abort.



End RegAlloc.
