(* receipt.ml *)

[%%import "/src/config.mlh"]

open Core_kernel
module B58_lib = Base58_check
open Snark_params.Tick

module Signed_command_elt = struct
  type t = Signed_command_payload of Signed_command.Payload.t
end

module Zkapp_command_elt = struct
  type t = Zkapp_command_commitment of Random_oracle.Digest.t
end

module Chain_hash = struct
  include Data_hash.Make_full_size (struct
    let description = "Receipt chain hash"

    let version_byte = Base58_check.Version_bytes.receipt_chain_hash
  end)

  (* Data hash versioned boilerplate below *)

  [%%versioned
  module Stable = struct
    [@@@no_toplevel_latest_type]

    module V1 = struct
      module T = struct
        type t = (Field.t[@version_asserted]) [@@deriving sexp, compare, hash]
      end

      include T

      let to_latest = Fn.id

      [%%define_from_scope to_yojson, of_yojson]

      include Comparable.Make (T)
      include Hashable.Make_binable (T)
    end
  end]

  let (_ : (t, Stable.Latest.t) Type_equal.t) = Type_equal.T

  let equal = Stable.Latest.equal

  let empty = of_hash Random_oracle.(salt "CodaReceiptEmpty" |> digest)

  let cons_signed_command_payload (e : Signed_command_elt.t) (t : t) =
    let open Random_oracle.Legacy in
    let x =
      match e with
      | Signed_command_payload payload ->
          Transaction_union_payload.(
            to_input_legacy (of_user_command_payload payload))
    in
    Input.(append x (field (t :> Field.t)))
    |> pack_input
    |> hash ~init:Hash_prefix.receipt_chain_signed_command
    |> of_hash

  (* prepend account_update index computed by Zkapp_command_logic.apply *)
  let cons_zkapp_command_commitment (index : Mina_numbers.Index.t)
      (e : Zkapp_command_elt.t) (t : t) =
    let open Random_oracle in
    let x =
      match e with Zkapp_command_commitment s -> Input.Chunked.field s
    in
    let index_input = Mina_numbers.Index.to_input index in
    Input.Chunked.(append index_input (append x (field (t :> Field.t))))
    |> pack_input
    |> hash ~init:Hash_prefix.receipt_chain_zkapp_command
    |> of_hash

  [%%if defined consensus_mechanism]

  module Checked = struct
    module Signed_command_elt = struct
      type t = Signed_command_payload of Transaction_union_payload.var
    end

    module Zkapp_command_elt = struct
      type t = Zkapp_command_commitment of Random_oracle.Checked.Digest.t
    end

    let constant (t : t) =
      var_of_hash_packed (Field.Var.constant (t :> Field.t))

    type t = var

    let equal t1 t2 = equal_var t1 t2

    let if_ = if_

    let cons_signed_command_payload (e : Signed_command_elt.t) t =
      let open Random_oracle.Legacy in
      let%bind x =
        match e with
        | Signed_command_payload payload ->
            let%map payload =
              Transaction_union_payload.Checked.to_input_legacy payload
            in
            payload
      in
      make_checked (fun () ->
          Checked.hash ~init:Hash_prefix.receipt_chain_signed_command
            (Checked.pack_input Input.(append x (field (var_to_hash_packed t))))
          |> var_of_hash_packed )

    (* prepend account_update index *)
    let cons_zkapp_command_commitment (index : Mina_numbers.Index.Checked.t)
        (e : Zkapp_command_elt.t) (t : t) =
      let open Random_oracle in
      let%bind x =
        match e with
        | Zkapp_command_commitment s ->
            Let_syntax.return (Input.Chunked.field s)
      in
      let index_input = Mina_numbers.Index.Checked.to_input index in
      make_checked (fun () ->
          Checked.hash ~init:Hash_prefix.receipt_chain_zkapp_command
            (Checked.pack_input
               Input.Chunked.(
                 append index_input (append x (field (var_to_hash_packed t)))) )
          |> var_of_hash_packed )
  end

  let%test_unit "checked-unchecked equivalence (signed command)" =
    let open Quickcheck in
    test ~trials:20 (Generator.tuple2 gen Signed_command_payload.gen)
      ~f:(fun (base, payload) ->
        let unchecked =
          cons_signed_command_payload (Signed_command_payload payload) base
        in
        let checked =
          let comp =
            let open Snark_params.Tick.Checked.Let_syntax in
            let payload =
              Transaction_union_payload.(
                Checked.constant (of_user_command_payload payload))
            in
            let%map res =
              Checked.cons_signed_command_payload
                (Signed_command_payload payload) (var_of_t base)
            in
            As_prover.read typ res
          in
          Or_error.ok_exn (run_and_check comp)
        in
        assert (equal unchecked checked) )

  let%test_unit "checked-unchecked equivalence (zkapp_command)" =
    let open Quickcheck in
    test ~trials:20 (Generator.tuple2 gen Field.gen)
      ~f:(fun (base, commitment) ->
        let index_int = 17 in
        let unchecked =
          let index = Mina_numbers.Index.of_int index_int in
          cons_zkapp_command_commitment index
            (Zkapp_command_commitment commitment) base
        in
        let checked =
          let open Snark_params.Tick.Checked.Let_syntax in
          let comp =
            let%bind index =
              let open Mina_numbers.Index.Checked in
              let rec go acc (n : int) =
                if Int.equal n 0 then return acc
                else
                  let%bind acc' = succ acc in
                  go acc' (n - 1)
              in
              go zero index_int
            in
            let commitment = Field.Var.constant commitment in
            let%map res =
              Checked.cons_zkapp_command_commitment index
                (Zkapp_command_commitment commitment) (var_of_t base)
            in
            As_prover.read typ res
          in
          Or_error.ok_exn (run_and_check comp)
        in
        assert (equal unchecked checked) )

  let%test_unit "json" =
    Quickcheck.test ~trials:20 gen ~sexp_of:sexp_of_t ~f:(fun t ->
        assert (Codable.For_tests.check_encoding (module Stable.Latest) ~equal t) )

  [%%endif]
end
