(*
 * connection.mli
 * --------------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

(** Interface for dbus connection *)

type t
  (** Abstract type for a connection *)

type guid = Address.guid
    (** Unique identifier of a server *)

(** {6 Creation} *)

val of_transport : ?shared:bool -> Transport.t -> t
  (** [of_transport shared transport] create a dbus connection over
      the given transport. If [shared] is true and a connection to the
      same server is already open, then it is used instead of
      [transport], this is the default behaviour. *)

val of_addresses : ?shared:bool -> Address.t list -> t
  (** [of_addresses shared addresses] shorthand for obtaining
      transport and doing [of_transport] *)

(** {6 Sending messages} *)

(** Note: these functions take a complete message description, you may
    have a look at [Message] for easy creation of messages *)

type body = Values.values
type send_message = Header.send * body
type recv_message = Header.recv * body

val send_message_sync : t -> send_message -> recv_message
  (** [send_message_sync connection message] send a message over a
      DBus connection.

      Note: the serial field of the header will always be filled
      automatically *)

val send_message_async : t -> send_message -> (recv_message -> unit) -> unit
  (** same as send_message_sync but return immediatly and register a
      function for receiving the result *)

val send_message_no_reply : t -> send_message -> unit
  (** same as send_message_sync but do not expect a reply *)

(** {6 Dispatching} *)

val dispatch : t -> unit
  (** [dispatch bus] read and dispatch one message. If using threads
      [dispatch] do nothing. *)

type filter = Header.recv -> body Lazy.t -> bool
  (** A filter is a function that take a message, do something with
      and return true if the message can be considered has "handled"
      or false if other filters must be called on it. *)

val add_filter : t -> filter -> unit
  (** [add_filter connection filter] add a filter to the connection.
      This filter will be called before all previously defined
      filter *)

val add_interface : t -> 'a Interface.t -> unit
  (** [add_interface connection interface] add handling of an
      interface to the connection.

      Method calls on this interface will be dispatched and the
      connection will also handle introspection *)

(** {6 Informations} *)

val transport : t -> Transport.t
  (** [transport connection] get the transport associated with a
      connection *)

val guid : t -> guid
  (** [guid connection] return the unique identifier of the server *)

(**/**)

open Wire

type 'a reader = Header.recv -> buffer -> ptr -> 'a
type writer = Header.byte_order -> buffer -> ptr -> buffer * ptr

val raw_send_message_sync : t -> Header.send -> writer -> 'a reader -> 'a
val raw_send_message_async : t -> Header.send -> writer -> unit reader -> unit
val raw_send_message_no_reply : t -> Header.send -> writer -> unit
val raw_add_filter : t -> bool reader -> unit

val read_values : Values.values reader
val write_values : Values.values -> writer
