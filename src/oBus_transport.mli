(*
 * oBus_transport.mli
 * ------------------
 * Copyright : (c) 2009, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implementation of D-Bus.
 *)

(** Low-level transporting of messages *)

type t
  (** Type of message transport *)

val recv : t -> OBus_message.t Lwt.t
  (** [recv tr] receives one message from the given transport *)

val send : t -> OBus_message.t -> unit Lwt.t
  (** [send tr msg] sends [msg] over the transport [tr]. *)

val shutdown : t -> unit Lwt.t
  (** [shutdown tr] free resources allocated by the given transport *)

val make :
  recv : (unit -> OBus_message.t Lwt.t) ->
  send : (OBus_message.t -> unit Lwt.t) ->
  shutdown : (unit -> unit Lwt.t) -> t
  (** [make ~recv ~send ~shutdown] creates a new transport from the
      given functions.

      Notes:
      - message reading/writing are serialized by obus, so there is no
      need to handle concurrent access to transport
  *)

val loopback : unit -> t
  (** Loopback transport, each message sent is received on the same
      transport *)

val of_addresses :
  ?mechanisms : OBus_auth.Client.mechanism list ->
  OBus_address.t list ->
  (OBus_address.guid * t) Lwt.t
    (** Try to make a working transport from a list of
        addresses. Return also the guid of the server address *)
