(*
 * obus_introspect.ml
 * ------------------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

open OBus_interface

let recursive = ref false
let mli = ref false
let anons = ref []
let session = ref false
let system = ref false
let obj_mode = ref false

let args = [
  "-rec", Arg.Set recursive, "introspect recursively all sub-nodes";
  "-caml", Arg.Set mli, "print in caml style instead of xml";
  "-session", Arg.Set session, "the service is on the session bus (the default)";
  "-system", Arg.Set system, "the service is on the system bus";
  "-objects", Arg.Set obj_mode, "list objects with interfaces they implements instead of interfaces";
]

let usage_msg = Printf.sprintf "Usage: %s <option> <destination> <path>
Introspect a DBus service (print only interfaces).
options are:" (Filename.basename (Sys.argv.(0)))

open Lwt

module Interf_map = Map.Make(struct type t = string let compare = compare end)

let rec get proxy =
  lwt interfaces, subs = OBus_proxy.introspect proxy in
  let map = List.fold_left (fun map (name, content, annots) ->
                              Interf_map.add name (content, annots) map)
    Interf_map.empty interfaces in
  let nodes = [(proxy, List.map (fun (name, _, _) -> name) interfaces)] in
  match !recursive with
    | true ->
        List.fold_left
          (fun t1 t2 ->
             lwt nodes1, map1 = t1 and nodes2, map2 = t2 in
             return (nodes1 @ nodes2, Interf_map.fold Interf_map.add map1 map2))
          (return (nodes, map)) (List.map get subs)
    | false ->
        return (nodes, map)

let main service path =
  lwt bus = Lazy.force begin match !session, !system with
    | true, true ->
        prerr_endline "must specify at most one of -session, -system\n\n";
        Arg.usage args usage_msg;
        exit 1
    | false, false
    | true, false -> OBus_bus.session
    | false, true -> OBus_bus.system
  end in
  lwt nodes, map = get (OBus_proxy.make (OBus_peer.make bus service) path) in
  begin
    match !obj_mode with
      | false ->
          begin match !mli with
            | false ->
                print_endline (Xml.to_string_fmt
                                 (OBus_introspect.to_xml
                                    (Interf_map.fold (fun name (content, annots) acc -> (name, content, annots) :: acc) map [], [])))
            | true ->
                Interf_map.iter (fun name (content, annots) ->
                                   Print.print_proxy_interf Format.std_formatter (name, content, annots))
                  map
          end
      | true ->
          List.iter begin fun (proxy, interfaces) ->
            print_endline (OBus_path.to_string (OBus_proxy.path proxy));
            List.iter (Printf.printf " + %s\n") interfaces;
            print_newline ();
          end nodes
  end;
  return ()

let () =
  Arg.parse args
    (fun arg -> anons := arg :: !anons)
    usage_msg;

  let service, path = match !anons with
    | [path; service] -> (service, OBus_path.of_string path)
    | _ -> Arg.usage args usage_msg; exit 1
  in
  try
    Lwt_main.run (main service path)
  with
    | Xml.Error _
    | OBus_introspect.Parse_failure _ ->
        prerr_endline "invalid introspection document returned by the service!";
        exit 1
