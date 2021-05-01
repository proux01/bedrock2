Require Import Coq.derive.Derive.
Require Import coqutil.Z.Lia.
Require coqutil.Word.BigEndian coqutil.Word.ZifyLittleEndian.
Require Import coqutil.Word.LittleEndianList.
Require Import coqutil.Byte coqutil.Datatypes.HList.
Require Import coqutil.Datatypes.PropSet.
Require Import coqutil.Tactics.letexists coqutil.Tactics.Tactics coqutil.Tactics.rewr coqutil.Tactics.rdelta.
Require Import coqutil.Tactics.rewr.
Require Import coqutil.Map.Interface coqutil.Map.Properties coqutil.Map.OfListWord.
Require Import coqutil.Word.Interface coqutil.Word.Properties.
Require Import bedrock2.Syntax bedrock2.Semantics.
Require Import bedrock2.NotationsCustomEntry coqutil.Z.HexNotation.
Require Import bedrock2.FE310CSemantics.
Require Import bedrock2.Lift1Prop.
Require Import bedrock2.Map.Separation bedrock2.Map.SeparationLogic bedrock2.Array.
Require Import bedrock2.ZnWords.
Require Import bedrock2.ptsto_bytes bedrock2.Scalars.
Require Import bedrock2.WeakestPrecondition bedrock2.ProgramLogic.
Require Import bedrock2.ZnWords.
Require Import coqutil.Word.SimplWordExpr.
Require Import coqutil.Tactics.Records.
Require Import coqutil.Tactics.Simp.
Require Import bedrock2.MetricLogging.
Require Import bedrock2.footpr.
Require Import bedrock2.StringIdentConversion.

Local Set Nested Proofs Allowed.

(* TODO put into coqutil and also use in lightbulb.v *)
Module word. Section WithWord.
  Import ZArith.
  Local Open Scope Z_scope.
  Context {width} {word: word.word width} {ok : word.ok word}.
  Lemma unsigned_of_Z_nowrap x:
    0 <= x < 2 ^ width -> word.unsigned (word.of_Z x) = x.
  Proof.
    intros. rewrite word.unsigned_of_Z. unfold word.wrap. rewrite Z.mod_small; trivial.
  Qed.
  Lemma of_Z_inj_small{x y}:
    word.of_Z x = word.of_Z y -> 0 <= x < 2 ^ width -> 0 <= y < 2 ^ width -> x = y.
  Proof.
    intros. apply (f_equal word.unsigned) in H. rewrite ?word.unsigned_of_Z in H.
    unfold word.wrap in H. rewrite ?Z.mod_small in H by assumption. assumption.
  Qed.

  Lemma and_bool_to_word: forall (b1 b2: bool),
    word.and (if b1 then word.of_Z 1 else word.of_Z 0)
             (if b2 then word.of_Z 1 else word.of_Z 0) =
    if (andb b1 b2) then word.of_Z 1 else word.of_Z 0.
  Proof.
    assert (1 < 2 ^ width). {
      pose proof word.width_pos.
      change 1 with (2 ^ 0). apply Z.pow_lt_mono_r; blia.
    }
    destruct b1; destruct b2; simpl; apply word.unsigned_inj; rewrite word.unsigned_and;
      unfold word.wrap; rewrite ?unsigned_of_Z_nowrap by blia;
        rewrite ?Z.land_diag, ?Z.land_0_r, ?Z.land_0_l;
        apply Z.mod_small; blia.
  Qed.
End WithWord. End word.

Module List.
  Import List.ListNotations. Open Scope list_scope.
  Section MapWithIndex.
    Context {A B: Type} (f: A -> nat -> B).
    Fixpoint map_with_start_index(start: nat)(l: list A): list B :=
      match l with
      | nil => nil
      | h :: t => f h start :: map_with_start_index (S start) t
      end.
    Definition map_with_index: list A -> list B := map_with_start_index O.

    Lemma map_with_start_index_app: forall l l' start,
        map_with_start_index start (l ++ l') =
        map_with_start_index start l ++ map_with_start_index (start + List.length l) l'.
    Proof.
      induction l; intros.
      - simpl. rewrite PeanoNat.Nat.add_0_r. reflexivity.
      - simpl. f_equal. rewrite IHl. f_equal. f_equal. Lia.lia.
    Qed.

    Lemma map_with_index_app: forall l l',
        map_with_index (l ++ l') = map_with_index l ++ map_with_start_index (List.length l) l'.
    Proof. intros. apply map_with_start_index_app. Qed.

    Lemma map_with_start_index_cons: forall a l start,
        map_with_start_index start (a :: l) = f a start :: map_with_start_index (S start) l.
    Proof. intros. reflexivity. Qed.

    Lemma map_with_index_cons: forall a l,
        map_with_index (a :: l) = f a 0 :: map_with_start_index 1 l.
    Proof. intros. reflexivity. Qed.

    Lemma skipn_map_with_start_index: forall i start l,
        skipn i (map_with_start_index start l) = map_with_start_index (start + i) (skipn i l).
    Proof.
      induction i; intros.
      - simpl. rewrite PeanoNat.Nat.add_0_r. reflexivity.
      - destruct l; simpl. 1: reflexivity. rewrite IHi. f_equal. Lia.lia.
    Qed.

    Lemma map_with_start_index_nth_error: forall (n start: nat) (l: list A) d,
        List.nth_error l n = Some d ->
        List.nth_error (map_with_start_index start l) n = Some (f d (start + n)).
    Proof.
      induction n; intros.
      - destruct l; simpl in *. 1: discriminate. rewrite PeanoNat.Nat.add_0_r. congruence.
      - destruct l; simpl in *. 1: discriminate. erewrite IHn. 2: eassumption. f_equal. f_equal. Lia.lia.
    Qed.

    Lemma map_with_index_nth_error: forall (n: nat) (l : list A) d,
        List.nth_error l n = Some d ->
        List.nth_error (map_with_index l) n = Some (f d n).
    Proof. intros. eapply map_with_start_index_nth_error. assumption. Qed.

  End MapWithIndex.

  Section WithA.
    Context {A: Type}.

    Lemma nth_error_to_hd_skipn: forall n (l: list A) a d,
        List.nth_error l n = Some a ->
        hd d (skipn n l) = a.
    Proof.
      induction n; intros.
      - destruct l; simpl in *. 1: discriminate. congruence.
      - destruct l; simpl in *. 1: discriminate. eauto.
    Qed.

    Definition generate(len: nat)(f: nat -> A): list A := List.map f (List.seq 0 len).

    Lemma map_with_shifted_start_index{B: Type}: forall (f1 f2: A -> nat -> B) vs start1 start2,
        (forall a i, f1 a i = f2 a (i + start2 - start1)) ->
        map_with_start_index f1 start1 vs = map_with_start_index f2 start2 vs.
    Proof.
      induction vs; intros.
      - reflexivity.
      - simpl. f_equal.
        + rewrite H. f_equal. blia.
        + eapply IHvs. intros. rewrite H.
          f_equal. blia.
    Qed.

  End WithA.
End List.

Definition TODO{T: Type}: T. Admitted.

Infix "^+" := word.add  (at level 50, left associativity).
Infix "^-" := word.sub  (at level 50, left associativity).
Infix "^*" := word.mul  (at level 40, left associativity).
Infix "^<<" := word.slu  (at level 37, left associativity).
Infix "^>>" := word.sru  (at level 37, left associativity).
Notation "/[ x ]" := (word.of_Z x)       (* squeeze a Z into a word (beat it with a / to make it smaller) *)
  (format "/[ x ]").
Notation "\[ x ]" := (word.unsigned x)   (* \ is the open (removed) lid of the modulo box imposed by words, *)
  (format "\[ x ]").                     (* let a word fly into the large Z space *)

Section WithParameters.
  Context {p : FE310CSemantics.parameters}.
  Import Syntax BinInt String List.ListNotations ZArith.
  Local Set Implicit Arguments.
  Local Open Scope string_scope. Local Open Scope Z_scope. Local Open Scope list_scope.

  Coercion Z.of_nat : nat >-> Z.
  Coercion byte.unsigned : byte >-> Z.

  (* see COQBUG https://github.com/coq/coq/issues/4593 for why these aliases are needed to make coercions work *)
  Definition two_bytes := tuple byte 2.
  Definition four_bytes := tuple byte 4.

  (* These definitions and coercions are only needed to write source code, as soon as
     interpreted, they will go away because expr.literal will be removed by the interpreter. *)
  Coercion byte_to_expr(b: byte): expr := expr.literal (byte.unsigned b).
  Coercion two_bytes_to_expr(b: two_bytes): expr := expr.literal (LittleEndian.combine 2 b).
  Coercion four_bytes_to_expr(b: four_bytes): expr := expr.literal (LittleEndian.combine 4 b).

  Coercion expr.literal : Z >-> expr.
  Coercion expr.var : String.string >-> expr.

  Notation len := List.length.
  Notation "'bytetuple' sz" := (HList.tuple byte (@Memory.bytes_per width sz)) (at level 10).

  Add Ring wring : (Properties.word.ring_theory (word := Semantics.word))
        (preprocess [autorewrite with rew_word_morphism],
         morphism (Properties.word.ring_morph (word := Semantics.word)),
         constants [Properties.word_cst]).

  (* TODO move (to Scalars.v?) *)
  Lemma load_bounded_Z_of_sep: forall sz addr (value: Z) R m,
      0 <= value < 2 ^ (Z.of_nat (bytes_per (width:=width) sz) * 8) ->
      sep (truncated_scalar sz addr value) R m ->
      Memory.load_Z sz m addr = Some value.
  Proof.
    intros.
    cbv [load scalar littleendian load_Z] in *.
    erewrite load_bytes_of_sep. 2: exact H0.
    apply f_equal.
    rewrite LittleEndian.combine_split.
    apply Z.mod_small.
    assumption.
  Qed.

  Lemma load_of_sep_truncated_scalar: forall sz addr (value: Z) R m,
      0 <= value < 2 ^ (Z.of_nat (bytes_per (width:=width) sz) * 8) ->
      sep (truncated_scalar sz addr value) R m ->
      Memory.load sz m addr = Some (word.of_Z value).
  Proof.
    intros. unfold Memory.load.
    erewrite load_bounded_Z_of_sep by eassumption.
    reflexivity.
  Qed.

  Lemma bytearray_index_split_iff1: forall a (l: list byte) n,
      word.unsigned n <= Z.of_nat (List.length l) ->
      iff1 (array ptsto /[1] a l)
           (sep (array ptsto /[1] a (List.firstn (Z.to_nat (word.unsigned n)) l))
                (array ptsto /[1] (a ^+ n) (List.skipn (Z.to_nat (word.unsigned n)) l))).
  Proof.
    intros.
    etransitivity.
    2: {
      symmetry. eapply bytearray_index_merge. ZnWords.
    }
    rewrite List.firstn_skipn.
    reflexivity.
  Qed.

  Lemma bytearray_index_split: forall a (l: list byte) n,
      word.unsigned n <= Z.of_nat (List.length l) ->
      array ptsto /[1] a l =
      sep (array ptsto /[1] a (List.firstn (Z.to_nat (word.unsigned n)) l))
          (array ptsto /[1] (a ^+ n) (List.skipn (Z.to_nat (word.unsigned n)) l)).
  Proof. intros. eapply iff1ToEq. eapply bytearray_index_split_iff1. assumption. Qed.

  Definition bytesAt(addr: word)(bs: list byte): mem -> Prop :=
    eq (map.of_list_word_at addr bs).

  Definition bytesAtWithLen(addr: word)(l: Z)(bs: list byte): mem -> Prop :=
    sep (emp (l = len bs)) (eq (map.of_list_word_at addr bs)).

  Notation "a |-> bs" := (bytesAt a bs) (at level 12).
  Notation "a ,+ l |-> bs" := (bytesAtWithLen a l bs)
    (at level 12, l at level 0, format "a ,+ l  |->  bs").

  Definition BEBytesToWord{n: nat}(bs: tuple byte n): word := word.of_Z (BigEndian.combine n bs).

  Definition ZToBEWord(n: nat)(x: Z): word := BEBytesToWord (BigEndian.split n x).

  Definition byteToWord(b: byte): word := word.of_Z (byte.unsigned b).

  (* An n-byte unsigned little-endian number v at address a.
     Enforces that v fits into n bytes. *)
  Definition LEUnsigned(n: nat)(addr: word)(v: Z)(m: mem): Prop :=
    exists bs: tuple byte n, ptsto_bytes n addr bs m /\ v = LittleEndian.combine n bs.

  (* Enforces that v fits into (bytes_per sz) bytes.
     To be used as the one and only base-case separation logic assertion, because using
     load1/2/4/8 will convert the value it puts into the dst register to word anyways,
     so it makes sense to hardcode the type of v to be word. *)
  Definition value(sz: access_size)(addr v: word): mem -> Prop :=
    LEUnsigned (bytes_per (width:=width) sz) addr (word.unsigned v).

  Lemma load_of_sep_value: forall sz addr v R m,
      sep (value sz addr v) R m ->
      Memory.load sz m addr = Some v.
  Proof.
    unfold value, Memory.load, Memory.load_Z, LEUnsigned. intros.
    assert (exists bs : tuple Init.Byte.byte (bytes_per sz),
               sep (ptsto_bytes (bytes_per sz) addr bs) R m /\
               word.unsigned v = LittleEndian.combine (bytes_per (width:=width) sz) bs) as A. {
      unfold sep in *.
      decompose [ex and] H.
      eauto 10.
    }
    clear H. destruct A as (bs & A & E).
    erewrite load_bytes_of_sep by eassumption.
    rewrite <- E.
    rewrite word.of_Z_unsigned.
    reflexivity.
  Qed.

  Inductive TypeSpec: Type -> Type :=
  | TByte: TypeSpec byte
  | TStruct{R: Type}(fields: list (FieldSpec R)): TypeSpec R
  (* dynamic number of elements: *)
  | TArray{E: Type}(elemSize: Z)(elemSpec: TypeSpec E): TypeSpec (list E)
  (* number of elements statically known: *)
  | TTuple{E: Type}(count: nat)(elemSize: Z)(elemSpec: TypeSpec E): TypeSpec (tuple E count)
  with FieldSpec: Type -> Type :=
  | FField{R F: Type}(getter: R -> F)(setter: R -> F -> R)(fieldSpec: TypeSpec F)
    : FieldSpec R.

  Fixpoint TypeSpec_size{R: Type}(sp: TypeSpec R): R -> Z :=
    match sp with
    | TByte => fun r => 1
    | TStruct fields => fun r => List.fold_right (fun f res => FieldSpec_size f r + res) 0 fields
    | TArray elemSize _ => fun l => List.length l * elemSize
    | TTuple n elemSize _ => fun t => n * elemSize
    end
  with FieldSpec_size{R: Type}(f: FieldSpec R): R -> Z :=
    match f with
    | FField getter setter sp => fun r => TypeSpec_size sp (getter r)
    end.

  (* sum of the sizes of the first i fields *)
  Definition offset{R: Type}(r: R)(fields: list (FieldSpec R))(i: nat): Z :=
    List.fold_right (fun f res => FieldSpec_size f r + res) 0 (List.firstn i fields).

  Section dataAt_recursion_helpers.
    Context (dataAt: forall {R: Type}, TypeSpec R -> word -> R -> mem -> Prop).

    Definition fieldAt{R: Type}(f: FieldSpec R)(i: nat): list (FieldSpec R) -> word -> R -> mem -> Prop :=
      match f with
      | FField getter setter sp => fun fields base r => dataAt sp (base ^+ /[offset r fields i]) (getter r)
      end.

    Definition fieldsAt{R: Type}(fields: list (FieldSpec R))(start: word)(r: R): list (mem -> Prop) :=
      List.map_with_index (fun f i => fieldAt f i fields start r) fields.

    Definition arrayAt{E: Type}(elemSize: Z)(elem: TypeSpec E)(start: word): list E -> list (mem -> Prop) :=
      List.map_with_index (fun e i => dataAt elem (start ^+ /[i * elemSize]) e).

    Definition dataAt_body{R: Type}(sp: TypeSpec R): word -> R -> mem -> Prop :=
      match sp with
      | TByte => ptsto
      | @TStruct R fields => fun base r => seps (fieldsAt fields base r)
      | @TArray E elemSize elem => fun base l => seps (arrayAt elemSize elem base l)
      | @TTuple E n elemSize elem => fun base t => seps (arrayAt elemSize elem base (tuple.to_list t))
      end.
  End dataAt_recursion_helpers.

  Fixpoint dataAt{R: Type}(sp: TypeSpec R){struct sp}: word -> R -> mem -> Prop := dataAt_body (@dataAt) sp.

  Section UpdateHelpers.
    Context (update: forall {R: Type}, TypeSpec R -> list byte -> R -> R).

    Definition update_field{R: Type}(sp: FieldSpec R)(bs: list byte): R -> R :=
      match sp in (FieldSpec T) return (T -> T) with
      | FField getter setter fieldSpec => fun r => setter r (update fieldSpec bs (getter r))
      end.

    Fixpoint update_fields{R: Type}(fields: list (FieldSpec R))(bs: list byte)(r: R): R :=
      match fields with
      | [] => r
      | f :: fs => update_field f bs (update_fields fs (List.skipn (Z.to_nat (FieldSpec_size f r)) bs) r)
      end.

    Section WithTypeSpec.
      Context {E: Type}(elemSize: Z)(sp: TypeSpec E).
      Fixpoint update_array(bs: list byte)(l: list E): list E.
        refine (match bs with
                | nil => l
                | b :: bs' => _
                end).
        destruct l.
        - exact nil.
        - refine (let e' := _ in
                  e' :: update_array (List.skipn (Z.to_nat elemSize) bs) l).
          refine (update sp bs e).
      Defined.

      Fixpoint update_tuple{n: nat}(bs: list byte)(l: tuple E n){struct n}: tuple E n.
        refine (match bs with
                | nil => l
                | b :: bs' => _
                end).
        destruct n.
        - exact l.
        - destruct l as [e l].
          refine (let e' := update sp bs e in
                  PrimitivePair.pair.mk e' (update_tuple n (List.skipn (Z.to_nat elemSize) bs) l)).
      Defined.
    End WithTypeSpec.

    Definition update_body{R: Type}(sp: TypeSpec R)(bs: list byte): R -> R :=
      match sp in (TypeSpec T) return (T -> T) with
      | TByte => fun b => List.hd b bs
      | TStruct fields => update_fields fields bs
      | TArray elemSize elemSpec => update_array elemSize elemSpec bs
      | TTuple count elemSize elemSpec => update_tuple elemSize elemSpec bs
      end.
  End UpdateHelpers.

  Fixpoint update{R: Type}(sp: TypeSpec R)(bs: list byte): R -> R :=
    update_body (@update) sp bs.

  Class Flatten(R: Type) := flatten: R -> list byte.

  (* ** Packet Formats *)

  Definition ETHERTYPE_ARP: two_bytes := tuple.of_list [Byte.x08; Byte.x06].
  Definition ETHERTYPE_IPV4: two_bytes := tuple.of_list [Byte.x08; Byte.x00].

  Definition MAC := tuple byte 6.

  Definition IPv4 := tuple byte 4.

  Record EthernetPacket(Payload: Type) := mkEthernetARPPacket {
    dstMAC: MAC;
    srcMAC: MAC;
    etherType: tuple byte 2; (* <-- must initially accept all possible two-byte values *)
    payload: Payload;
  }.

  Instance flatten_byte: Flatten byte := fun b => [b].

  Instance flatten_byte_tuple(n: nat): Flatten (tuple byte n) := tuple.to_list.

  (* TODO some typeclass search + Ltac hackery could infer these typeclass instances *)
  Instance flatten_EthernetPacket(Payload: Type){flPld: Flatten Payload}: Flatten (EthernetPacket Payload) :=
    fun r => flatten r.(dstMAC) ++ flatten r.(srcMAC) ++ flatten r.(etherType) ++ flatten r.(payload).

  Definition EthernetPacket_spec{Payload: Type}(Payload_spec: TypeSpec Payload) := TStruct [
    FField (@dstMAC Payload) TODO (TTuple 6 1 TByte);
    FField (@srcMAC Payload) TODO (TTuple 6 1 TByte);
    FField (@etherType Payload) TODO (TTuple 2 1 TByte);
    FField (@payload Payload) TODO Payload_spec
  ].

  Record ARPPacket := mkARPPacket {
    htype: tuple byte 2; (* hardware type *)
    ptype: tuple byte 2; (* protocol type *)
    hlen: byte;          (* hardware address length (6 for MAC addresses) *)
    plen: byte;          (* protocol address length (4 for IPv4 addresses) *)
    oper: tuple byte 2;
    sha: MAC;  (* sender hardware address *)
    spa: IPv4; (* sender protocol address *)
    tha: MAC;  (* target hardware address *)
    tpa: IPv4; (* target protocol address *)
  }.

  Instance flatten_ARPPacket: Flatten ARPPacket :=
    fun r => flatten r.(htype) ++ flatten r.(ptype) ++ flatten r.(hlen) ++ flatten r.(plen) ++
             flatten r.(oper) ++ flatten r.(sha) ++ flatten r.(spa) ++ flatten r.(tha) ++ flatten r.(tpa).

  Definition ARPPacket_spec: TypeSpec ARPPacket := TStruct [
    FField htype TODO (TTuple 2 1 TByte);
    FField ptype TODO (TTuple 2 1 TByte);
    FField hlen TODO TByte;
    FField plen TODO TByte;
    FField oper TODO (TTuple 2 1 TByte);
    FField sha TODO (TTuple 6 1 TByte);
    FField spa TODO (TTuple 4 1 TByte);
    FField tha TODO (TTuple 6 1 TByte);
    FField tpa TODO (TTuple 4 1 TByte)
  ].

  Definition HTYPE: two_bytes := tuple.of_list [Byte.x00; Byte.x01].
  Definition PTYPE: two_bytes := tuple.of_list [Byte.x80; Byte.x00].
  Definition HLEN: byte := Byte.x06.
  Definition PLEN: byte := Byte.x04.
  Definition OPER_REQUEST: two_bytes := tuple.of_list [Byte.x00; Byte.x01].
  Definition OPER_REPLY: two_bytes := tuple.of_list [Byte.x00; Byte.x02].

  Definition validPacket(pk: EthernetPacket ARPPacket): Prop :=
    (pk.(etherType) = ETHERTYPE_ARP \/ pk.(etherType) = ETHERTYPE_IPV4) /\
    pk.(payload).(htype) = HTYPE /\
    pk.(payload).(ptype) = PTYPE /\
    pk.(payload).(hlen) = HLEN /\
    pk.(payload).(plen) = PLEN /\
    (pk.(payload).(oper) = OPER_REQUEST \/ pk.(payload).(oper) = OPER_REPLY).

  Record ARPConfig := mkARPConfig {
    myMAC: MAC;
    myIPv4: IPv4;
  }.

  Context (cfg: ARPConfig).

  Definition needsARPReply(req: EthernetPacket ARPPacket): Prop :=
    req.(etherType) = ETHERTYPE_ARP /\
    req.(payload).(oper) = OPER_REQUEST /\
    req.(payload).(tpa) = cfg.(myIPv4). (* <-- we only reply to requests asking for our own MAC *)

  Definition ARPReply(req: EthernetPacket ARPPacket): EthernetPacket ARPPacket :=
    {| dstMAC := req.(payload).(sha);
       srcMAC := cfg.(myMAC);
       etherType := ETHERTYPE_ARP;
       payload := {|
         htype := HTYPE;
         ptype := PTYPE;
         hlen := HLEN;
         plen := PLEN;
         oper := OPER_REPLY;
         sha := cfg.(myMAC); (* <-- the actual reply *)
         spa := cfg.(myIPv4);
         tha := req.(payload).(sha);
         tpa := req.(payload).(spa)
       |}
    |}.

  Fixpoint firstn_as_tuple{A: Type}(default: A)(n: nat)(l: list A): tuple A n :=
    match n as n return tuple A n with
    | O => tt
    | S m => PrimitivePair.pair.mk (List.hd default l) (firstn_as_tuple default m (List.tl l))
    end.

  Lemma to_list_firstn_as_tuple: forall A (default: A) n (l: list A),
      (n <= List.length l)%nat ->
      tuple.to_list (firstn_as_tuple default n l) = List.firstn n l.
  Proof.
    induction n; intros.
    - reflexivity.
    - destruct l. 1: cbv in H; exfalso; blia.
      simpl in *.
      f_equal. eapply IHn. blia.
  Qed.

  Ltac unfold1dataAt :=
    lazymatch goal with
    | |- context[@dataAt ?R ?sp] => change (@dataAt R sp) with (dataAt_body (@dataAt) sp)
    end;
    cbv beta iota delta [dataAt_body].

  Lemma array_arrayAt: forall {R: Type} sz sp (vs: list R) addr,
      seps (arrayAt (@dataAt) sz sp addr vs) = array (dataAt sp) /[sz] addr vs.
  Proof.
    induction vs; intros.
    - simpl. reflexivity.
    - etransitivity. {
        eapply iff1ToEq. symmetry. eapply seps'_iff1_seps.
      }
      simpl.
      simpl_word_exprs word_ok.
      eapply iff1ToEq.
      cancel.
      cbv [seps].
      rewrite seps'_iff1_seps.
      rewrite <- IHvs.
      unfold arrayAt, List.map_with_index.
      erewrite (List.map_with_shifted_start_index _ _ _ 0). 1: reflexivity.
      intros. simpl. f_equal. ZnWords.
  Qed.

  Lemma fill_dummy_with_bytes: forall {R: Type} (sp: TypeSpec R) (dummy: R) a bs,
      TypeSpec_size sp dummy = len bs ->
      iff1 (array ptsto /[1] a bs) (dataAt sp a (update sp bs dummy)).
  Proof.
    induction sp; intros.
    - simpl in *. destruct bs. 1: discriminate. destruct bs. 2: {
        cbn in H. exfalso. blia.
      }
      simpl.
      cancel.
    - simpl in *.
      revert a bs H.
      induction fields; intros.
      + simpl in *. destruct bs. 2: discriminate.
        simpl. cancel.
      + change (@update_fields (@update) ?R (?f :: ?fs) ?bs ?r) with
               (update_field (@update) f bs
                             (update_fields (@update) fs (List.skipn (Z.to_nat (FieldSpec_size f r)) bs) r)).
        unfold fieldsAt.
        rewrite List.map_with_index_cons.
        rewrite <- seps'_iff1_seps. cbn [seps']. rewrite seps'_iff1_seps.
        change (List.fold_right ?f ?x (?h :: ?t)) with (f h (List.fold_right f x t)) in H.
        cbv beta in H.
        assert (0 <= List.fold_right (fun f res => FieldSpec_size f dummy + res) 0 fields). {
          exact TODO.
        }
        assert (0 <= FieldSpec_size a dummy). {
          exact TODO.
        }
        rewrite (bytearray_index_split a0 bs /[(FieldSpec_size a dummy)]) by ZnWords.
        cancel.
        cancel_seps_at_indices O O. {
          eapply iff1ToEq. etransitivity.
          - eapply IHfields.
            replace (List.fold_right (fun (f : FieldSpec R) (res : Z) => FieldSpec_size f dummy + res) 0 fields)
              with (len bs - FieldSpec_size a dummy) by blia.
            assert (len bs >= 0) by admit.
            rewrite List.firstn_length.

            (* needs IH for sp, ie needs mutual induction principle for TypeSpec *)
  Admitted.

  Lemma bytesToARPPacket: forall a bs,
      28 = len bs ->
      exists p: ARPPacket,
        iff1 (array ptsto /[1] a bs) (dataAt ARPPacket_spec a p).
  Proof.
    intros.
    eexists {| oper := _ |}. cbn -[tuple.to_list].

  Admitted.

  Lemma bytesToEthernetARPPacket: forall a bs,
      64 = len bs ->
      exists p: EthernetPacket ARPPacket,
        iff1 (array ptsto /[1] a bs) (dataAt (EthernetPacket_spec ARPPacket_spec) a p).
  Proof.
    intros.
    eexists (update (EthernetPacket_spec ARPPacket_spec) bs _).
    change (@update ?R ?sp) with (update_body (@update) sp).
    cbv beta iota delta [update_body].
    unfold EthernetPacket_spec.
  Abort.

  Lemma bytesToEthernetARPPacket0: forall a bs,
      64 = len bs ->
      exists p: EthernetPacket ARPPacket,
        iff1 (array ptsto /[1] a bs) (dataAt (EthernetPacket_spec ARPPacket_spec) a p).
  Proof.
    intros.
    eexists {| payload := _ |}.
    unfold1dataAt.
    unfold EthernetPacket_spec.
    unfold fieldsAt, List.map_with_index, List.map_with_start_index.
    unfold fieldAt.
    simpl_getters_applied_to_constructors.
    unfold offset, List.fold_right, List.firstn.
    unfold FieldSpec_size.
    unfold seps.
    simpl_word_exprs word_ok.
    cancel.

    ParamRecords.simpl_param_projections.

    lazymatch goal with
    | |- iff1 (seps [array ptsto /[1] ?addr ?vs]) (seps (dataAt ?sp ?addr ?v :: _)) =>
      let s := eval cbv in (TypeSpec_size sp v) in idtac s;
      rewrite (bytearray_index_split addr vs /[s]) by ZnWords
    end.
    cbn [seps]. cancel.
    cancel_seps_at_indices O O. {
      unfold1dataAt.
      rewrite array_arrayAt.
      f_equal.
      replace (Z.to_nat \[/[6]]) with 6%nat by ZnWords.
      symmetry.
      apply to_list_firstn_as_tuple.
      ZnWords.
    }

    lazymatch goal with
    | |- iff1 (seps [array ptsto /[1] ?addr ?vs]) (seps (dataAt ?sp ?addr ?v :: _)) =>
      let s := eval cbv in (TypeSpec_size sp v) in idtac s;
      rewrite (bytearray_index_split addr vs /[s]) by ZnWords
    end.
    cbn [seps]. cancel.
    cancel_seps_at_indices O O. {
      unfold1dataAt.
      rewrite array_arrayAt.
      f_equal.
      replace (Z.to_nat \[/[6]]) with 6%nat by ZnWords.
      symmetry.
      apply to_list_firstn_as_tuple.
      ZnWords.
    }

    replace (a ^+ /[6] ^+ /[6]) with (a ^+ /[12]) by ZnWords.

    lazymatch goal with
    | |- iff1 (seps [array ptsto /[1] ?addr ?vs]) (seps (dataAt ?sp ?addr ?v :: _)) =>
      let s := eval cbv in (TypeSpec_size sp v) in idtac s;
      rewrite (bytearray_index_split addr vs /[s]) by ZnWords
    end.
    cbn [seps]. cancel.
    cancel_seps_at_indices O O. {
      unfold1dataAt.
      rewrite array_arrayAt.
      f_equal.
      replace (Z.to_nat \[/[2]]) with 2%nat by ZnWords.
      symmetry.
      apply to_list_firstn_as_tuple.
      ZnWords.
    }

    rewrite ?List.skipn_skipn.
    cbn [seps].

    (* existential is annoying, maybe define a function filling a TypeSpec starting from a list of
       bytes? *)

    (* TODO messy *)
  Admitted.

  Lemma bytesToEthernetARPPacket: forall bs,
      42 = len bs ->
      exists p: EthernetPacket ARPPacket,
        bs = flatten p.
  Proof.
    intros.
    repeat (destruct bs as [|? bs]; [discriminate H|]).
    destruct bs. 2: {
      exfalso. cbn [List.length] in H. blia.
    }
    clear H.
    eexists.
    repeat match goal with
           | |- context[?e] => is_evar e;
                                 let t := type of e in
                                 lazymatch t with
                                 | Coq.Init.Byte.byte => fail
                                 | _ => instantiate_evar_with_econstructor e
                                 end
           end.
    cbn.
    reflexivity.
  Qed.

  Definition addr_in_range(a start: word)(len: Z): Prop :=
    word.unsigned (word.sub a start) <= len.

  Definition subrange(start1: word)(len1: Z)(start2: word)(len2: Z): Prop :=
    0 <= len1 <= len2 /\ addr_in_range start1 start2 (len2-len1).

(*
  Notation "a ,+ m 'c=' b ,+ n" := (subrange a m b n)
    (no associativity, at level 10, m at level 1, b at level 1, n at level 1,
     format "a ,+ m  'c='  b ,+ n").
*)

  Record dummy_packet := {
    dummy_src: tuple byte 4;
 (* if we want dependent field types (instead of just dependent field lengths), we also need
    to figure out how to set/update such fields...
    dummy_dst_kind: bool;
    dummy_dst: if dummy_dst_kind then tuple byte 4 else tuple byte 6;
    *)
    dummy_dst: tuple byte 4;
    dummy_len: tuple byte 2;
    dummy_data: list byte;
    dummy_padding: list byte (* non-constant offset *)
  }.

  Definition set_dummy_src d x :=
    Build_dummy_packet x (dummy_dst d) (dummy_len d) (dummy_data d) (dummy_padding d).
  Definition set_dummy_dst d x :=
    Build_dummy_packet (dummy_src d) x (dummy_len d) (dummy_data d) (dummy_padding d).
  Definition set_dummy_len d x :=
    Build_dummy_packet (dummy_src d) (dummy_dst d) x (dummy_data d) (dummy_padding d).
  Definition set_dummy_data d x :=
    Build_dummy_packet (dummy_src d) (dummy_dst d) (dummy_len d) x (dummy_padding d).
  Definition set_dummy_padding d x :=
    Build_dummy_packet (dummy_src d) (dummy_dst d) (dummy_len d) (dummy_data d) x.

  Definition dummy_spec: TypeSpec dummy_packet := TStruct [
    FField dummy_src set_dummy_src (TTuple 4 1 TByte);
    FField dummy_dst set_dummy_dst (TTuple 4 1 TByte);
    FField dummy_len set_dummy_len (TTuple 2 1 TByte);
    FField dummy_data set_dummy_data (TArray 1 TByte);
    FField dummy_padding set_dummy_padding (TArray 1 TByte)
  ].

  Record foo := {
    foo_count: tuple byte 4;
    foo_packet: dummy_packet;
    foo_packets: list dummy_packet;
  }.
  Definition set_foo_count f x :=
    Build_foo x (foo_packet f) (foo_packets f).
  Definition set_foo_packet f x :=
    Build_foo (foo_count f) x (foo_packets f).
  Definition set_foo_packets f x :=
    Build_foo (foo_count f) (foo_packet f) x.

  Definition foo_spec: TypeSpec foo := TStruct [
    FField foo_count set_foo_count (TTuple 4 1 TByte);
    FField foo_packet set_foo_packet dummy_spec;
    FField foo_packets set_foo_packets (TArray 256 dummy_spec)
  ].

  (* append-at-front direction (for constructing a path using backwards reasoning) *)
  Inductive lookup_path:
    (* input: start type, end type, *)
    forall {R F: Type},
    (* type spec, base address, and whole value found at empty path *)
    TypeSpec R -> word -> R ->
    (* output: type spec, address and value found at given path *)
    TypeSpec F -> word -> F -> Prop :=
  | lookup_path_Nil: forall R R' (sp: TypeSpec R) (sp': TypeSpec R') addr addr' r r',
      dataAt sp addr r = dataAt sp' addr' r' ->
      lookup_path sp addr r
                  sp' addr' r'
  | lookup_path_Field: forall R F R' (getter: R -> F) setter fields i sp sp' addr addr' (r: R) (r': R'),
      List.nth_error fields i = Some (FField getter setter sp) ->
      lookup_path sp (addr ^+ /[offset r fields i]) (getter r)
                  sp' addr' r' ->
      lookup_path (TStruct fields) addr r
                  sp' addr' r'
  | lookup_path_Index: forall R E (sp: TypeSpec R) r' len i (sp': TypeSpec E) l e addr addr',
      List.nth_error l i = Some e ->
      lookup_path sp (addr ^+ /[i * len]) e
                  sp' addr' r' ->
      lookup_path (TArray len sp) addr l
                  sp' addr' r'.

  Ltac assert_lookup_range_feasible :=
    match goal with
    | |- lookup_path ?sp ?addr ?v ?sp' ?addr' ?v' =>
      let range_start := eval cbn -[Z.add] in addr in
      let range_size := eval cbn -[Z.add] in (TypeSpec_size sp v) in
      let target_start := addr' in
      let target_size := eval cbn -[Z.add] in (TypeSpec_size sp' v') in
      assert (subrange target_start target_size range_start range_size)
(*    assert (target_start,+target_size c= range_start,+range_size)*)
    end.

  Ltac check_lookup_range_feasible :=
    assert_succeeds (assert_lookup_range_feasible; [solve [unfold subrange, addr_in_range; ZnWords]|]).

  Axiom admit_implication: forall (P Q: Prop), P -> Q.
  Arguments admit_implication: clear implicits.

  Lemma record_simplification: forall (P Q: Prop), P = Q -> P -> Q. Proof. intros. subst P. assumption. Qed.
  Arguments record_simplification: clear implicits.

Require Import Ltac2.Ltac2.
Require Ltac2.Option.
Set Default Proof Mode "Classic".

Ltac2 Type exn ::= [ Succeeds ].

Ltac2 without_effects(t: unit -> 'a) :=
  let r := { contents := t (* <- dummy default *) } in
  match Control.case (fun () =>
         match Control.case t with
         | Val p => match p with
                    | (x, _) => r.(contents) := (fun () => x); Control.zero Succeeds
                    end
         | Err e => Control.zero e
         end) with
  | Val _ => Control.throw (Tactic_failure (Some (Message.of_string "anomaly")))
  | Err e =>
    match e with
    | Succeeds => r.(contents) ()
    | _ => Control.zero e
    end
  end.

  Ltac admit_cbn_old :=
    match goal with
    | |- ?G => let G' := eval cbn in G in apply (admit_implication G' G)
    end.

  Ltac2 admit_transform(t: unit -> unit) :=
    let g' := without_effects (fun () => t (); Control.goal ()) in apply (admit_implication $g').

  Ltac2 record_transform(t: unit -> unit) :=
    let g' := without_effects (fun () => t (); Control.goal ()) in apply (record_simplification $g' _ eq_refl).

  Ltac2 admit_cbn () := admit_transform (fun () => cbn).

  Ltac admit_cbn := ltac2:(Control.enter admit_cbn).

  Ltac admit_reflexivity :=
    match goal with
    | |- ?lhs = ?rhs => unify lhs rhs; exact TODO
    end.

  Goal forall base f R m,
      seps [dataAt foo_spec base f; R] m ->
      exists v,
        lookup_path foo_spec base f
                    (TTuple 2 1 TByte) (base ^+ /[12]) v.
  Proof.
    intros.

    Check f.(foo_packet).(dummy_len).
    eexists.

    (*Eval simpl in (path_value (PField (PField (PNil _) foo_packet) dummy_len) f).*)

    (* t = load2(base ^+ /[4] ^+ /[8])
       The range `(base+12),+2` corresponds to the field `f.(foo_packet).(dummy_len)`.
       Goal: use lia to find this path. *)
    set (target_start := (base ^+ /[12])).
    set (target_size := 2%Z).

    (* backward reasoning: *)

    (* check that path is still good *)
    match goal with
    | |- lookup_path ?sp ?addr ?v _ _ _ =>
      pose (range_start := addr); cbn -[Z.add] in range_start;
      pose (range_size := (TypeSpec_size sp v)); cbn -[Z.add] in range_size
    end.
    assert (subrange target_start target_size range_start range_size) as T. {
      unfold subrange, addr_in_range. ZnWords.
    }
    clear range_start range_size T.

    eapply lookup_path_Field with (i := 1%nat); [reflexivity|]. (* <-- i picked by backtracking *)
    admit_cbn.

    (* check that path is still good *)
    check_lookup_range_feasible.

    eapply lookup_path_Field with (i := 2%nat). { admit_reflexivity. } (* <-- i picked by backtracking *)
    admit_cbn.

    (* check that path is still good *)
    check_lookup_range_feasible.

    eapply lookup_path_Nil.
    f_equal.

  try eapply word.unsigned_inj;
  lazymatch goal with
  | |- ?G => is_lia_prop G
  end.
  cleanup_for_ZModArith.
  simpl_list_length_exprs.
  unfold_Z_nat_consts.
  (* PARAMRECORDS *)
  simpl.
  canonicalize_word_width_and_instance.
  repeat wordOps_to_ZModArith_step.
  dewordify;
  clear_unused_nonProps.
  better_lia.
  Qed.

  (* ** Program logic rules *)

Section WithWordPostAndMemAndLocals.

  Implicit Type post: word -> Prop.
  Context (m: mem) (l: locals).

(* firstn_as_tuple,
   or load precondition with builtin sublist *)
  Inductive wp_expr: expr.expr -> (word -> Prop) -> Prop :=
  | wp_expr_literal: forall v post,
      post (word.of_Z v) ->
      wp_expr (expr.literal v) post
  | wp_expr_var: forall x v post,
      map.get l x = Some v ->
      post v ->
      wp_expr (expr.var x) post
  | wp_expr_op_raw: forall op e1 e2 mid post,
      wp_expr e1 mid ->
      (forall v1, mid v1 -> wp_expr e2 (fun v2 => post (interp_binop op v1 v2))) ->
      wp_expr (expr.op op e1 e2) post
  | wp_expr_load: forall sz e post,
      wp_expr e (fun a => exists bs R,
        seps [a,+(bytes_per (width:=width) sz) |-> bs; R] m /\
        post /[le_combine bs]) ->
      wp_expr (expr.load sz e) post
  | wp_expr_inlinetable: forall s t e post,
      wp_expr e (fun a => load s (map.of_list_word t) a post) ->
      wp_expr (expr.inlinetable s t e) post.

  Lemma wp_expr_op: forall op e1 e2 post,
      wp_expr e1 (fun v1 => wp_expr e2 (fun v2 => post (interp_binop op v1 v2))) ->
      wp_expr (expr.op op e1 e2) post.
  Proof. intros. eauto using wp_expr_op_raw. Qed.

  Lemma wp_expr_sound: forall e post,
      wp_expr e post ->
      forall mc, exists v mc', eval_expr m l e mc = Some (v, mc') /\ post v.
  Proof. (* automation test case *)
    induction 1; intros; cbn -[map.get]; ParamRecords.simpl_param_projections.
    - eauto.
    - rewrite_match. eauto.
    - edestruct IHwp_expr. decompose [and ex] H2. rewrite H4. edestruct H1. 1: eassumption.
      decompose [and ex] H3. rewrite H7. eauto.
    - edestruct IHwp_expr. decompose [and ex] H0. rewrite H2.
      exact TODO.
    - edestruct IHwp_expr. decompose [and ex] H0. rewrite H2.
      unfold load in *. decompose [and ex] H3. ParamRecords.simpl_param_projections. rewrite H4. eauto.
  Qed.

End WithWordPostAndMemAndLocals.

  (* We have two rules for conditionals depending on whether there are more commands afterwards *)

  Lemma if_split: forall e c thn els t m l mc post,
      wp_expr m l c (fun b =>
                       (word.unsigned b <> 0 -> exec e thn t m l mc post) /\
                       (word.unsigned b =  0 -> exec e els t m l mc post)) ->
    exec e (cmd.cond c thn els) t m l mc post.
  Admitted.

  Lemma if_merge: forall e t m l mc c thn els rest post,
      wp_expr m l c (fun b => exists Q1 Q2,
                         (word.unsigned b <> 0 -> exec e thn t m l mc Q1) /\
                         (word.unsigned b = 0  -> exec e els t m l mc Q2) /\
                         (forall t' m' l' mc', word.unsigned b <> 0 /\ Q1 t' m' l' mc' \/
                                               word.unsigned b = 0  /\ Q2 t' m' l' mc' ->
                                               exec e rest t' m' l' mc' post)) ->
      exec e (cmd.seq (cmd.cond c thn els) rest) t m l mc post.
  Admitted.

  Lemma assignment: forall e x_name a t m l mc rest post,
      wp_expr m l a
        (fun x_val => forall mc x_var, x_var = x_val -> exec e rest t m (map.put l x_name x_var) mc post) ->
      exec e (cmd.seq (cmd.set x_name a) rest) t m l mc post.
  Proof.
    intros. eapply wp_expr_sound in H. simp.
    eapply exec.seq_cps.
    eapply exec.set. 1: eassumption.
    eapply Hp1.
    reflexivity.
  Qed.

  Lemma loop: forall e cond body rest t m l mc (inv: trace -> mem -> locals -> MetricLogging.MetricLog -> Prop) post,
      inv t m l mc ->
      (forall ti mi li mci, inv ti mi li mci ->
         wp_expr mi li cond (fun b =>
           (word.unsigned b <> 0 -> exec e body ti mi li mci inv) /\
           (word.unsigned b =  0 -> exec e rest ti mi li mci post))) ->
      exec e (cmd.seq (cmd.while cond body) rest) t m l mc post.
  Abort. (* TODO needs a termination measure, maybe using metrics? *)

  (* no init clause included because after init we need to reshape symbolic
     state into loop invariant
     for (;i < hi; i += d) body
   *)
  Definition for_up(i: string)(hi: expr)(d: Z)(body: cmd): cmd :=
    (cmd.while (expr.op bopname.ltu i hi)
               (cmd.seq body (cmd.set i (expr.op bopname.add i d)))).

  (* TODO PARAMRECORDS where is the correct location to put this? *)
  Existing Instance SortedListString.ok.

  Lemma while_cps: forall e cond body t m l mc0 mc post b,
      eval_expr m l cond mc0 = Some (b, mc) ->
      (word.unsigned b <> 0 -> exec e body t m l mc (fun t' m' l' mc' =>
        exec e (cmd.while cond body) t' m' l'
             (addMetricInstructions 2 (addMetricLoads 2 (addMetricJumps 1 mc'))) post)) ->
      (word.unsigned b = 0 -> post t m l (addMetricInstructions 1 (addMetricLoads 1 (addMetricJumps 1 mc)))) ->
      exec e (cmd.while cond body) t m l mc0 post.
  Proof.
    intros. destruct (Z.eqb_spec (word.unsigned b) 0) as [Eq | Neq].
    - eauto using exec.while_false.
    - eauto using exec.while_true.
  Qed.

  Lemma for_loop_up: forall i hi d (inv: trace -> mem -> locals -> MetricLogging.MetricLog -> Prop) v_lo v_hi
      e body t m l mc (post: trace -> mem -> locals -> MetricLogging.MetricLog -> Prop),
      0 < d ->
      map.get l i = Some v_lo ->
      inv t m l mc ->
      (forall ti mi li mci v_i, inv ti mi li mci -> map.get li i = Some v_i ->
         wp_expr mi li hi (fun v_hi' =>
             word.unsigned v_hi' = v_hi /\ (* <-- upper bound needs to evaluate to same value each time *)
             (word.unsigned v_i < v_hi ->
              forall mc', exec e body ti mi li mc' (fun t' m' l' mc' =>
                map.get l' i = Some v_i /\ (* <-- value of i unchanged during loop body *)
                forall mc'', inv t' m' (map.put l' i (word.add v_i (word.of_Z d))) mc'')) /\
             (v_hi <= word.unsigned v_i -> forall mc'', post ti mi li mc''))) ->
      v_hi + d <= 2^width ->
      exec e (for_up i hi d body) t m l mc post.
  Proof.
    intros *. intros dLB Glo I0 B hiUB.
    unfold for_up.
    pose proof (well_founded_ind (Z.lt_wf (- 2 ^ width))) as Ind.
    cbv beta in Ind.
    remember (v_hi - word.unsigned v_lo) as fuel.
    revert I0.
    revert dependent v_lo.
    revert t m l mc.
    induction fuel using Ind. clear Ind.
    intros. subst.
    specialize B with (1 := I0). specialize B with (1 := Glo).
    eapply wp_expr_sound in B. destruct B as (v_hi' & mc''' & Evhi & E1 & Again & Done).
    subst.
    eapply while_cps.
    - cbn [eval_expr]. rewrite Glo. rewrite Evhi. reflexivity.
    - intros Neq. cbn in Neq. rewrite word.unsigned_ltu in Neq. destruct_one_match_hyp. 2: exfalso; ZnWords.
      eapply exec.seq.
      + eapply Again. assumption.
      + cbv zeta beta. intros *. intros (Eq1 & Ii).
        eapply exec.set. {
          cbn [eval_expr]. rewrite Eq1. reflexivity.
        }
        eapply H. 3: reflexivity. 2: {
          rewrite map.get_put_same. reflexivity.
        }
        { cbn [interp_binop]. ZnWords. }
        { cbn [interp_binop]. apply Ii. }
    - intros Eq. cbn in Eq. eapply Done.
      rewrite word.unsigned_ltu in Eq. destruct_one_match_hyp. 1: exfalso; ZnWords. exact E.
  Qed.

(*
  Lemma call:

list_map
spec_of

        bind_ex args <- dexprs m l arges;
        call fname t m args (fun t m rets =>
          bind_ex_Some l <- map.putmany_of_list_zip binds rets l;
          post t m l)

exec.call
*)

(*
  Implicit Type post: trace -> mem -> locals -> MetricLogging.MetricLog -> Prop.
*)

  Lemma seps_nth_error_to_head: forall i Ps P,
      List.nth_error Ps i = Some P ->
      iff1 (seps Ps) (sep P (seps (app (firstn i Ps) (tl (skipn i Ps))))).
  Proof.
    intros.
    etransitivity.
    - symmetry. eapply seps_nth_to_head.
    - eapply List.nth_error_to_hd_skipn in H. rewrite H. reflexivity.
  Qed.

  Lemma expose_lookup_path: forall R F sp base (r: R) sp' addr (v: F),
      lookup_path sp base r sp' addr v ->
      exists Frame, iff1 (dataAt sp base r) (sep (dataAt sp' addr v) Frame).
  Proof.
    induction 1.
    - subst. exists (emp True). rewrite H. cancel.
    - destruct IHlookup_path as [Frame IH]. simpl in IH.
      eexists.
      cbn.
      unfold fieldsAt at 1.
      eapply List.map_with_index_nth_error in H.
      rewrite seps_nth_error_to_head. 2: exact H.
      unfold fieldAt at 1.
      rewrite IH.
      ecancel.
    - destruct IHlookup_path as [Frame IH]. simpl in IH.
      eexists.
      cbn.
      unfold arrayAt at 1.
      eapply List.map_with_index_nth_error in H.
      rewrite seps_nth_error_to_head. 2: exact H.
      rewrite IH.
      ecancel.
  Qed.

  Lemma load_field0: forall sz m addr M i R sp (r: R) base (v: bytetuple sz),
      seps M m ->
      List.nth_error M i = Some (dataAt sp base r) ->
      lookup_path sp base r (TTuple _ 1 TByte) addr v ->
      Memory.load_bytes (bytes_per sz) m addr = Some v.
  Proof.
    intros.
    destruct (expose_lookup_path H1) as (Frame & P).
    cbn in P.
    simpl in P.
    eapply seps_nth_error_to_head in H0.
    eapply H0 in H.
    seprewrite_in P H.
    eapply load_bytes_of_sep.
    replace (ptsto_bytes (bytes_per sz) addr v) with (seps (arrayAt (@dataAt) 1 TByte addr (tuple.to_list v)))
      by exact TODO.
    simpl. (* PARAMRECORDS *)
    ecancel_assumption.
  Qed.

  Lemma load_field: forall sz m addr M i R sp (r: R) base v,
      seps M m ->
      List.nth_error M i = Some (dataAt sp base r) ->
      lookup_path sp base r (TTuple _ 1 TByte) addr v ->
      Memory.load sz m addr = Some /[LittleEndian.combine (bytes_per (width:=width) sz) v].
  Proof.
    intros.
    unfold Memory.load, Memory.load_Z.
    erewrite load_field0; eauto.
  Qed.

  (* optimized for easy backtracking *)
  Lemma load_field': forall sz m addr M R sp (r: R) base v,
      seps M m ->
      (exists i,
          List.nth_error M i = Some (dataAt sp base r) /\
          lookup_path sp base r (TTuple _ 1 TByte) addr v) ->
      Memory.load sz m addr = Some /[LittleEndian.combine (bytes_per (width:=width) sz) v].
  Proof.
    intros. destruct H0 as (i & ? & ?). eauto using load_field.
  Qed.

  Lemma load_field'': forall sz m addr R sp (r: R) base v (post: word -> Prop),
      (exists M,
        seps M m /\
        exists i,
          List.nth_error M i = Some (dataAt sp base r) /\
          lookup_path sp base r (TTuple _ 1 TByte) addr v /\
          post /[LittleEndian.combine (bytes_per (width:=width) sz) v]) ->
      WeakestPrecondition.load sz m addr post.
  Proof.
    intros. unfold WeakestPrecondition.load. firstorder eauto using load_field.
  Qed.

  Lemma tuple_byte_1: forall addr v,
      dataAt TByte addr v = dataAt (TTuple 1 1 TByte) addr (tuple.of_list [v]).
  Proof. intros. simpl. f_equal. ZnWords. Qed.


  Local Notation function_t :=
    ((String.string * (list String.string * list String.string * Syntax.cmd.cmd))%type).
  Local Notation functions_t := (list function_t).

  Definition callees_correct(callee_specs: list (functions_t -> Prop))(functions: functions_t): Prop :=
    List.Forall (fun P => P functions) callee_specs.

  Definition vc_func (f: list (functions_t -> Prop) * function_t)
                     (t: trace) (m: mem) (argvs: list word)
                     (post : trace -> mem -> list word -> Prop) :=
    let '(callee_specs, (fname, (innames, outnames, body))) := f in
    forall functions: functions_t,
    callees_correct callee_specs functions ->
    exists l, map.of_list_zip innames argvs = Some l /\ forall mc,
      exec (map.of_list functions) body t m l mc (fun t' m' l' mc' =>
        list_map (WeakestPrecondition.get l') outnames (fun retvs => post t' m' retvs)).

(* backtrackingly tries all nats strictly smaller than n *)
Ltac pick_nat n :=
  multimatch n with
  | S ?m => constr:(m)
  | S ?m => pick_nat m
  end.

  Definition nFields{A: Type}(sp: TypeSpec A): option nat :=
    match sp with
    | TStruct fields => Some (List.length fields)
    | _ => None
    end.

  Ltac lookup_field_step := once (
    let n := lazymatch goal with
    | |- lookup_path ?sp ?base ?r _ _ _ =>
      let l := eval cbv in (nFields sp) in
      lazymatch l with
      | Some ?n => n
      end
    end in
    let j := pick_nat n in
    eapply lookup_path_Field with (i := j); [admit_reflexivity|]; admit_cbn;
    check_lookup_range_feasible).

  Ltac lookup_done :=
    eapply lookup_path_Nil; first [ apply tuple_byte_1 | f_equal; ZnWords ].

Ltac2 constr_to_ident(x: constr) :=
  match Constr.Unsafe.kind x with
  | Constr.Unsafe.Var i => i
  | _ => Control.throw (Invalid_argument (Some (Message.concat (Message.of_constr x)
                                                               (Message.of_string " is not an ident"))))
  end.

Ltac2 hyp_exists(x: ident) :=
  match Control.case (fun () => Control.hyp x) with
  | Val _ => true
  | Err _ => false
  end.

Ltac2 rename_with_stringname(x: ident)(name: constr) :=
  let x' := string_to_ident name in
  if hyp_exists x' then let x'' := Fresh.in_goal x' in Std.rename [(x', x'')] else ();
  Std.rename [(x, x')].

Ltac rename_with_stringname :=
  ltac2:(x name |- rename_with_stringname (constr_to_ident (Option.get (Ltac1.to_constr x)))
                                          (Option.get (Ltac1.to_constr name))).

Ltac cleanup_step :=
  match goal with
  | x : Word.Interface.word.rep _ |- _ => clear x
  | x : Semantics.word |- _ => clear x
  | x : Init.Byte.byte |- _ => clear x
  | x : Semantics.locals |- _ => clear x
  | x : Semantics.trace |- _ => clear x
  | x : Syntax.cmd |- _ => clear x
  | x : Syntax.expr |- _ => clear x
  | x : MetricLog |- _ => clear x
  | x : coqutil.Map.Interface.map.rep |- _ => clear x
  | x : BinNums.Z |- _ => clear x
  | x : unit |- _ => clear x
  | x : bool |- _ => clear x
  | x : list _ |- _ => clear x
  | x : nat |- _ => clear x
  | x := _ : Word.Interface.word.rep _ |- _ => clear x
  | x := _ : Semantics.word |- _ => clear x
  | x := _ : Init.Byte.byte |- _ => clear x
  | x := _ : Semantics.locals |- _ => clear x
  | x := _ : Semantics.trace |- _ => clear x
  | x := _ : Syntax.cmd |- _ => clear x
  | x := _ : Syntax.expr |- _ => clear x
  | x := _ : MetricLog |- _ => clear x
  | x := _ : coqutil.Map.Interface.map.rep |- _ => clear x
  | x := _ : BinNums.Z |- _ => clear x
  | x := _ : unit |- _ => clear x
  | x := _ : bool |- _ => clear x
  | x := _ : list _ |- _ => clear x
  | x := _ : nat |- _ => clear x
  | |- _ -> ?DoesNotDepend => intro
  | |- forall var, _ =>
    let var' := fresh var in
    intro var';
    match goal with
    | |- context[@map.put string (@word.rep _ _) _ _ ?name ?var'] =>
      let name' := rdelta_var name in
      rename_with_stringname var' name'
    | |- _ => idtac
    end
  | |- let _ := _ in _ => intro
  | |- dlet.dlet ?v (fun x => ?P) => change (let x := v in P); intro
  | _ => progress (cbn [Semantics.interp_binop] in * )
  | H: exists x, _ |- _ => destruct H as [x H]
  | H: _ /\ _ |- _ => lazymatch type of H with
                      | _ <  _ <  _ => fail
                      | _ <  _ <= _ => fail
                      | _ <= _ <  _ => fail
                      | _ <= _ <= _ => fail
                      | _ => destruct H
                      end
  | x := ?y |- ?G => is_var y; subst x
  | x := word.of_Z ?y |- _ => match isZcst y with
                              | true => subst x
                              end
  | H: ?x = ?y |- _ => constr_eq x y; clear H
  | |- ~ _ => intro
  | H: _ :: _ = _ :: _ |- _ => injection H as
  | H: Some _ = Some _ |- _ => injection H as
  end.

Import WeakestPrecondition.

Ltac locals_step :=
  match goal with
  | _ => cleanup_step
  | |- @list_map _ _ (@get _ _) _ _ => unfold1_list_map_goal; cbv beta match delta [list_map_body]
  | |- @list_map _ _ _ nil _ => cbv beta match fix delta [list_map list_map_body]
  | |- @get _ _ _ _ => cbv beta delta [get]
  | |- map.get _ _ = Some ?e' =>
    let e := rdelta e' in
    is_evar e;
    let M := lazymatch goal with |- @map.get _ _ ?M _ _ = _ => M end in
    let __ := match M with @Semantics.locals _ => idtac end in
    let k := lazymatch goal with |- map.get _ ?k = _ => k end in
    once (let v := multimatch goal with x := context[@map.put _ _ M _ k ?v] |- _ => v end in
          (* cbv is slower than this, cbv with whitelist would have an enormous whitelist, cbv delta for map is slower than this, generalize unrelated then cbv is slower than this, generalize then vm_compute is slower than this, lazy is as slow as this: *)
          unify e v; exact (eq_refl (Some v)))
  | |- @coqutil.Map.Interface.map.get _ _ (@Semantics.locals _) _ _ = Some ?v =>
    let v' := rdelta v in is_evar v'; (change v with v'); exact eq_refl
  | |- ?x = ?y =>
    let y := rdelta y in is_evar y; change (x=y); exact eq_refl
  | |- ?x = ?y =>
    let x := rdelta x in is_evar x; change (x=y); exact eq_refl
  | |- ?x = ?y =>
    let x := rdelta x in let y := rdelta y in constr_eq x y; exact eq_refl
  | |- exists l', Interface.map.of_list_zip ?ks ?vs = Some l' /\ _ =>
    letexists; split; [exact eq_refl|] (* TODO: less unification here? *)
  | |- exists l', Interface.map.putmany_of_list_zip ?ks ?vs ?l = Some l' /\ _ =>
    letexists; split; [exact eq_refl|] (* TODO: less unification here? *)
  | |- exists x, ?P /\ ?Q =>
    let x := fresh x in refine (let x := _ in ex_intro (fun x => P /\ Q) x _);
                        split; [solve [repeat locals_step]|]
  end.

Ltac expr_step :=
  match goal with
  | _ => locals_step
  | |- wp_expr _ _ _ _ => first [ eapply wp_expr_literal
                                | eapply wp_expr_var
                                | eapply wp_expr_op
                                | eapply wp_expr_load
                                | eapply wp_expr_inlinetable ]
  | |- @list_map _ _ (@expr _ _ _) _ _ => unfold1_list_map_goal; cbv beta match delta [list_map_body]
  | |- @dexpr _ _ _ _ _ => cbv beta delta [dexpr]
  | |- @dexprs _ _ _ _ _ => cbv beta delta [dexprs]
  | |- @WeakestPrecondition.load _ _ _ _ _ => eapply load_field'';
       once (match goal with
             (* backtrack over choice of Hm in case there are several *)
             | Hm: seps ?lm ?m |- exists l, seps l ?m /\ _ =>
               exists lm; split; [exact Hm|];
               let n := eval cbv [List.length] in (List.length lm) in
                   (* backtrack over choice of i *)
                   let i := pick_nat n in
                   eexists i; split; [cbv [List.nth_error]; reflexivity|];
                   split; [ repeat (lookup_done || lookup_field_step) |]
             end)
  | |- @eq (@coqutil.Map.Interface.map.rep _ _ (@Semantics.locals _)) _ _ =>
    eapply SortedList.eq_value; exact eq_refl
  | |- True => exact I
  | |- False \/ _ => right
  | |- _ \/ False => left
  end.

Ltac ring_simplify_hyp_rec t H :=
  lazymatch t with
  | ?a = ?b => ring_simplify_hyp_rec a H || ring_simplify_hyp_rec b H
  | word.unsigned ?a => ring_simplify_hyp_rec a H
  | word.of_Z ?a => ring_simplify_hyp_rec a H
  | _ => progress ring_simplify t in H
  end.

Ltac ring_simplify_hyp H :=
  let t := type of H in ring_simplify_hyp_rec t H.

Lemma if_then_1_else_0_eq_0: forall (b: bool),
    word.unsigned (if b then word.of_Z 1 else word.of_Z 0) = 0 ->
    b = false.
Proof. intros; destruct b; [exfalso|reflexivity]. ZnWords. Qed.

Lemma if_then_1_else_0_neq_0: forall (b: bool),
    word.unsigned (if b then word.of_Z 1 else word.of_Z 0) <> 0 ->
    b = true.
Proof. intros; destruct b; [reflexivity|exfalso]. ZnWords. Qed.

Ltac simpli_getEq t :=
  match t with
  | context[@word.and ?wi ?wo (if ?b1 then _ else _) (if ?b2 then _ else _)] =>
    constr:(@word.and_bool_to_word wi wo _ b1 b2)
  | context[@word.unsigned ?wi ?wo (word.of_Z ?x)] => constr:(@word.unsigned_of_Z_nowrap wi wo _ x)
  | context[@word.of_Z ?wi ?wo (word.unsigned ?x)] => constr:(@word.of_Z_unsigned wi wo _ x)
  | context[LittleEndian.combine 1 (tuple.of_list [?b])] => constr:(LittleEndian.combine_1_of_list b)
  end.

(* random simplifications that make the goal easier to prove *)
Ltac simpli_step :=
  match goal with
  | |- _ => cleanup_step
  | |- _ => progress (rewr simpli_getEq in * by ZnWords)
  | H: word.unsigned (if ?b then _ else _) = 0 |- _ => apply if_then_1_else_0_eq_0 in H
  | H: word.unsigned (if ?b then _ else _) <> 0 |- _ => apply if_then_1_else_0_neq_0 in H
  | H: word.eqb ?x ?y = true  |- _ => apply (word.eqb_true  x y) in H
  | H: word.eqb ?x ?y = false |- _ => apply (word.eqb_false x y) in H
  | H: andb ?b1 ?b2 = true |- _ => apply (Bool.andb_true_iff b1 b2) in H
  | H: andb ?b1 ?b2 = false |- _ => apply (Bool.andb_false_iff b1 b2) in H
  | H: orb ?b1 ?b2 = true |- _ => apply (Bool.orb_true_iff b1 b2) in H
  | H: orb ?b1 ?b2 = false |- _ => apply (Bool.orb_false_iff b1 b2) in H
  | H: byte.unsigned _ = byte.unsigned _ |- _ => apply byte.unsigned_inj in H
  | H: LittleEndian.combine _ _ = LittleEndian.combine _ _  |- _ => apply LittleEndian.combine_inj in H
  | H: word.of_Z ?x = word.of_Z ?y |- _ =>
    assert (x = y) by (apply (word.of_Z_inj_small H); ZnWords); clear H
  | |- _ => progress simpl (bytes_per _) in *
  end.

(* random simplifications that make the goal more readable and might be expensive *)
Ltac pretty_step :=
  match goal with
  | H: _ |- _ => ring_simplify_hyp H
  | H: ?T |- _ => clear H; assert_succeeds (assert T by ZnWords)
  end ||
  simpl_Z_nat.

Hint Unfold validPacket needsARPReply : prover_unfold_hints.

(* partially proves postconditions, trying to keep the goal readable *)
Ltac prover_step :=
  match goal with
  | |- _ => progress locals_step
  | |- _ => progress simpli_step
  | |- ?P /\ ?Q => assert_fails (is_lia_prop P; is_lia_prop Q); split
  | |- _ => ZnWords
  | |- ?P \/ ?Q =>
    let t := (repeat prover_step; ZnWords) in
    tryif (assert_succeeds (assert (P -> False) by t)) then
      tryif (assert_succeeds (assert (Q -> False) by t)) then
        fail 1 "you are trying to prove False"
      else
        right
    else
      tryif (assert_succeeds (assert (Q -> False) by t)) then
        left
      else
        fail "not sure whether to try left or right side of \/"
  | |- _ => solve [auto]
  | |- _ => progress autounfold with prover_unfold_hints in *
  end.

Import Syntax.

Inductive snippet :=
| SSet(x: string)(e: expr)
| SIf(cond: expr)(merge: bool)
| SForUp(i0: string)(lo: expr)(i1: string)(hi: expr)(i2: string)(d: Z)
        (inv: trace -> mem -> locals -> MetricLogging.MetricLog -> Prop)
| SEnd
| SElse.

Inductive note_wrapper: string -> Type := mkNote(s: string): note_wrapper s.
Notation "s" := (note_wrapper s) (at level 200, only printing).
Ltac add_note s := let n := fresh "Note" in pose proof (mkNote s) as n; move n at top.

Ltac raw_add_snippet := constr:(false).
(* to disable all automatic steps after adding a snippet:
Ltac raw_add_snippet ::= constr:(true).
*)

Tactic Notation "suppress_if_raw" tactic(t) :=
  lazymatch raw_add_snippet with
  | true => idtac
  | false => t
  end.

Ltac add_snippet s :=
  lazymatch s with
  | SSet ?y ?e =>
    eapply assignment with (x_name := y) (a := e); suppress_if_raw (idtac; repeat expr_step)
  | SIf ?cond false =>
    eapply if_split with (c := cond); suppress_if_raw (idtac; repeat expr_step; split)
(*
  | SForUp ?i0 ?lo ?i1 ?hi ?i2 ?d ?inv =>
    tryif constr_eq i0 i1 then
      (tryif constr_eq i1 i2 then
          (eapply (@for_loop_up i0 lo hi d inv);
           [ suppress_if_raw (idtac;
               lazymatch goal with
               | |- 0 < ?step => lazymatch isZcst step with
                                 | true => reflexivity
                                 | _ => fail 1000 "increment" step "must be constant"
                                 end
               end)
           | suppress_if_raw (idtac; repeat expr_step)
           | ])
        else fail 1000 "must increment" i1 ", not" i2)
       else fail 1000 "must test" i0 ", not" i1
*)
  | SEnd => eapply exec.skip
  | SElse => suppress_if_raw (idtac;
               lazymatch goal with
               | H: note_wrapper "'else' expected" |- _ => clear H
               end)
  end;
  suppress_if_raw (idtac; repeat simpli_step; repeat simpli_step).

  Hint Resolve EthernetPacket_spec: TypeSpec_instances.
  Hint Resolve ARPPacket_spec: TypeSpec_instances.

  Goal TypeSpec (EthernetPacket ARPPacket). eauto 2 with TypeSpec_instances. all: fail. Abort.

  Ltac index_of_getter getter fields :=
    lazymatch fields with
    | FField getter _ _ :: _ => constr:(O)
    | FField _ _ _ :: ?tail => let r := index_of_getter getter tail in constr:(S r)
    end.

  Ltac offset_of_getter getter :=
    lazymatch type of getter with
    | ?R -> ?F =>
      let sp := constr:(ltac:(eauto 2 with TypeSpec_instances) : TypeSpec R) in
      lazymatch eval hnf in sp with
      | TStruct ?fields =>
        let i := index_of_getter getter fields in
        lazymatch eval cbn in (fun r: R => offset r fields i) with
        (* value-dependent offsets are not supported here *)
        | fun _ => ?x => x
        end
      end
    end.

  Goal False.
    let ofs := offset_of_getter (@dstMAC ARPPacket) in idtac ofs.
    let ofs := offset_of_getter (@srcMAC ARPPacket) in idtac ofs.
    let ofs := offset_of_getter (@etherType ARPPacket) in idtac ofs.
    let ofs := offset_of_getter (@payload ARPPacket) in idtac ofs.
    let ofs := offset_of_getter plen in idtac ofs.
    let ofs := offset_of_getter spa in idtac ofs.
  Abort.

Tactic Notation "$" constr(s) "$" := add_snippet s.

Notation "/*number*/ e" := e (in custom bedrock_expr at level 0, e constr at level 0).

Notation "base @ getter" :=
  (expr.op bopname.add base (expr.literal ltac:(let ofs := offset_of_getter getter in exact ofs)))
  (in custom bedrock_expr at level 6, left associativity, only parsing,
   base custom bedrock_expr, getter constr).

Declare Custom Entry snippet.

Notation "*/ s /*" := s (s custom snippet at level 100).
Notation "x = e ;" := (SSet x e) (in custom snippet at level 0, x ident, e custom bedrock_expr).
Notation "'if' ( e ) '/*merge*/' {" := (SIf e true) (in custom snippet at level 0, e custom bedrock_expr).
Notation "'if' ( e ) '/*split*/' {" := (SIf e false) (in custom snippet at level 0, e custom bedrock_expr).
Notation "}" := SEnd (in custom snippet at level 0).
Notation "'else' {" := SElse (in custom snippet at level 0).
Notation "'for' ( i0 = lo ; '/*invariant' inv '*/' i1 < hi ; i2 += d ) {" := (SForUp i0 lo i1 hi i2 d inv)
  (in custom snippet at level 0, i0 name, i1 name, i2 name,
   lo custom bedrock_expr, hi custom bedrock_expr, d constr, inv constr at level 0).

Set Default Goal Selector "1".

  (* void *memcpy(void *dest, const void *src, size_t n);   *)
  Definition memcpy: {f: list (functions_t -> Prop) * (string * (list string * list string * cmd)) &
    forall t m dst src n srcData oldDstData R,
    seps [dst,+\[n] |-> oldDstData; src,+\[n] |-> srcData; R] m ->
    vc_func f t m [dst; src; n] (fun t' m' retvs =>
      retvs = [] /\
      seps [dst,+\[n] |-> srcData; src,+\[n] |-> srcData; R] m')}.
  Proof.
    refine (existT _ (?[callee_specs], ("memcpy", (["dst"; "src"; "n"], [], ?[body]))) _).
    intros. cbv [vc_func]. intros functions CC.
    exists (map.of_list [("dst", dst); ("src", src); ("n", n)]). split. 1: reflexivity. intros.
    pose (_i := "i"). pose (_n := "n").

(*
Ltac raw_add_snippet ::= constr:(true).
*)

    $*/
    _i = /*number*/0;
    /*$. replace oldDstData
         with (List.firstn (Z.to_nat \[i]) srcData ++ List.skipn (Z.to_nat \[i]) oldDstData) in H. 2: {
           (* TODO automate *)
           subst i. replace (Z.to_nat \[/[0]]) with O by ZnWords. reflexivity.
         }
         assert (0 <= \[i] <= \[n]) by ZnWords. clear H0.
         move H at bottom.

         lazymatch goal with
         | |- exec _ _ ?t ?m ?l0 ?mc _ =>
           (* TODO should be remember_if_not_var *)
           is_var t; is_var m; remember l0 as l; is_var mc
         end.

         pose proof (conj Heql (conj H1 H)) as I0.
         (* don't "clear Heql H1 H", will be needed for sideconditions *)
         pattern i in I0.
         eapply ex_intro in I0.
         pattern t, m, l, mc in I0.
         eapply (@for_loop_up _i (expr.literal 0) 1). 3: exact I0.
         1: reflexivity.
         subst l. reflexivity.
         cbv beta.

         expr_step.
         expr_step.
         expr_step.
         expr_step.
         expr_step.

(*
    $*/
    for (_i = /*number*/0;
         /*invariant (fun t' m' l' mc' => exists dst src n i,
           l' = map.of_list [("dst", dst); ("src", src); ("n", n); ("i", i)] /\
           t' = t' /\
           seps [dst,+\[n] |-> (List.firstn (Z.to_nat \[i]) srcData ++ List.skipn (Z.to_nat \[i]) oldDstData);
                 src,+\[n] |-> srcData; R] m')
         */
         _i < _n; _i += 1) { /*$.
*)

  Admitted.

(* need precondition that for all used functions, map.get e f = Some (same as referenced during proof)

if assumptions of each function's correctness lemma is: "function map contains the following impl",
we need to transitively collect callees, not good

if assumptions of each function's correctness lemma is: "spec_of_func1 functionlist -> ..."
we only need non-transitive dependencies in hyps of each lemma


  program_logic_goal_for swap_swap
    (forall functions : list (prod string (prod (prod (list string) (list string)) cmd)),
     spec_of_swap functions -> spec_of_swap functions -> spec_of_swap_swap (swap_swap :: functions))

 *)

  Definition arp: {f: list (functions_t -> Prop) * (string * (list string * list string * cmd)) &
    forall t m ethbufAddr ethBufData L R,
      seps [ethbufAddr |-> ethBufData; R] m ->
      \[L] = len ethBufData ->
      vc_func f t m [ethbufAddr; L] (fun t' m' retvs =>
        t' = t /\ (
        (* Success: *)
        (retvs = [/[1]] /\ exists request,
            validPacket request /\
            needsARPReply request /\
            seps [ethbufAddr |-> flatten request; R] m /\
            seps [ethbufAddr |-> flatten (ARPReply request); R] m') \/
        (* Failure: *)
        (retvs = [/[0]] /\ (~ exists request,
            validPacket request /\
            needsARPReply request /\
            seps [ethbufAddr |-> flatten request; R] m)
         /\ seps [ethbufAddr |-> ethBufData; R] m')
      ))}.
    pose "ethbuf" as ethbuf. pose "ln" as ln. pose "doReply" as doReply. pose "tmp" as tmp.
    refine (existT _ (?[callee_specs], ("arp", ([ethbuf; ln], [doReply], ?[body]))) _).
    intros. cbv [vc_func]. intros functions CC. letexists. split. 1: subst l; reflexivity. intros.

(*
instantiate (callee_specs := _ :: _).
unfold callees_correct in CC.
pose proof (List.Forall_inv CC).
eapply List.Forall_inv_tail in CC.
*)

    $*/
    doReply = /*number*/0; /*$. $*/
    if (ln == /*number*/42) /*split*/ {
      /*$. assert (42 = len ethBufData) as HL by ZnWords.
           edestruct (bytesToEthernetARPPacket _ HL) as (pk & A). subst ethBufData.

(*
     $*/
      if ((load2(ethbuf @ (@etherType ARPPacket)) == ETHERTYPE_ARP) (* &
          (load2(ethbuf @ (@payload ARPPacket) @ htype) == HTYPE) &
          (load2(ethbuf @ (@payload ARPPacket) @ ptype) == PTYPE) &
          (load1(ethbuf @ (@payload ARPPacket) @ hlen) == HLEN) &
          (load1(ethbuf @ (@payload ARPPacket) @ plen) == PLEN) &
          (load2(ethbuf @ (@payload ARPPacket) @ oper) == coq:(LittleEndian.combine 2 OPER_REQUEST)) &
          (load4(ethbuf @ (@payload ARPPacket) @ tpa) == coq:(LittleEndian.combine 4 cfg.(myIPv4))) *) )
      /*split*/ { /*$.

repeat expr_step.

do 2 eexists.
split. {
  use_sep_assumption.
  instantiate (2 := List.firstn 2 (List.skipn 12 (flatten pk))).
  exact TODO.
}
repeat expr_step.
split. {
repeat simpli_step.

(* TODO more simplifications *)

call: memcpy

        (* copy sha and spa from the request into tha and tpa for the reply (same buffer), 6+4 bytes *)
        (* memcpy(ethbuf @ (@payload ARPPacket) @ tha, ethbuf @ (@payload ARPPacket) @ sha, /*number*/10); *)

        $*/
        doReply = /*number*/1; /*$.
        (* TODO *) $*/
      } /*$ .

{
repeat prover_step.


eexists.

(* TODO: in this example, it would be better to not instantiate with econstructor, but with pk,
   but what heuristic to choose to decide?
   Maybe first try no econstructor, see if it's solvable, then try econstructor, see if it's solvable,
   else stop and let user decide? *)
*)
all: exact TODO.

(*
$*/
    else { /*$. (* nothing to do *) $*/
    } /*$.
      eexists.
      split. 1: reflexivity.
      split. 1: reflexivity.
      right.
      split. 1: reflexivity.
      exact TODO.
*)
    Unshelve.
    all: try exact (word.of_Z 0).
    all: try exact nil.
    all: try (exact (fun _ => False)).
    all: try exact TODO.
  Time Defined.

  Goal False.
    let r := eval unfold arp in match arp with
                                | (existT _ (callee_specs, (fname, (argmanes, retnames, body))) _) => body
                                end
      in pose r.
  Abort.

End WithParameters.
