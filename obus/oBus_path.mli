(*
 * oBus_path.mli
 * -------------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

(** Manipulation of dbus object paths *)

type element = string
    (** A path component *)

type t = element list
   (** A complete path *)

(** {6 Construction} *)

val empty : t
  (** Empty path *)

val after : t -> t -> t option
  (** [after prefix path] if [path = prefix @ p] return [Some p], and
      [None] if not *)

val of_string : string -> t
  (** Create an object path from a string.

      @raise [OBus_string.Invalid_string] if the given string does not
      represent a valid object path *)

val to_string : t -> string
  (** Return a string representation of an object path *)

val escape : string -> element
  (** Escape an arbitrary string into a valid element *)

val unescape : element -> string

(** {6 Validation} *)

val test : OBus_string.tester
val test_element : OBus_string.tester
