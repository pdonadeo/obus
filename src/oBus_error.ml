(*
 * oBus_error.ml
 * -------------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

type name = string
type message = string
exception DBus of name * message
exception Unknown_method of message
exception Out_of_memory of message
exception No_reply of message

open Printf

let errors = ref
  [ "org.freedesktop.DBus.Error.Failed",
    ((fun msg -> Failure msg),
     (function
        | Failure msg -> Some msg
        | _ -> None));
    "org.freedesktop.DBus.Error.UnknownMethod",
    ((fun msg -> Unknown_method msg),
     (function
        | Unknown_method msg -> Some msg
        | _ -> None));
    "org.freedesktop.DBus.Error.OOM",
    ((fun msg -> Out_of_memory msg),
     (function
        | Out_of_memory msg -> Some msg
        | _ -> None));
    "org.freedesktop.DBus.Error.NoReply",
    ((fun msg -> No_reply msg),
     (function
        | No_reply msg -> Some msg
        | _ -> None)) ]

let make name msg =
  match OBus_util.assoc name !errors with
    | Some (maker, unmaker) -> maker msg
    | None -> DBus(name, msg)

let unmake = function
  | DBus(name, msg) -> Some(name, msg)
  | exn -> OBus_util.find_map (fun (name, (maker, unmaker)) ->
                            OBus_util.wrap_option (unmaker exn) (fun msg -> (name, msg))) !errors

let register name maker unmaker = errors := (name, (maker, unmaker)) :: !errors