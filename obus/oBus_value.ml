(*
 * oBus_value.ml
 * -------------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

open Format

(* +-----------------------+
   | DBus type definitions |
   +-----------------------+ *)

type tbasic =
  | Tbyte
  | Tboolean
  | Tint16
  | Tint32
  | Tint64
  | Tuint16
  | Tuint32
  | Tuint64
  | Tdouble
  | Tstring
  | Tsignature
  | Tobject_path
 with constructor

type tsingle =
  | Tbasic of tbasic
  | Tstructure of tsingle list
  | Tarray of tsingle
  | Tdict of tbasic * tsingle
  | Tvariant
 with constructor

type tsequence = tsingle list

type signature = tsequence

(* +----------------------------+
   | DBus types pretty-printing |
   +----------------------------+ *)

let string_of printer x =
  let buf = Buffer.create 42 in
  let pp = formatter_of_buffer buf in
  pp_set_margin pp max_int;
  printer pp x;
  pp_print_flush pp ();
  Buffer.contents buf

let rec print_seq left right sep f pp l =
  pp_print_string pp left;
  begin match l with
    | [] -> ()
    | x :: l ->
        pp_open_box pp 0;
        f pp x;
        List.iter (fprintf pp "%s@ %a" sep f) l;
        pp_close_box pp ()
  end;
  pp_print_string pp right

let print_list f = print_seq "[" "]" ";" f
let print_tuple f = print_seq "(" ")" "," f

let string_of_tbasic = function
  | Tbyte -> "Tbyte"
  | Tboolean -> "Tboolean"
  | Tint16 -> "Tint16"
  | Tint32 -> "Tint32"
  | Tint64 -> "Tint64"
  | Tuint16 -> "Tuint16"
  | Tuint32 -> "Tuint32"
  | Tuint64 -> "Tuint64"
  | Tdouble -> "Tdouble"
  | Tstring -> "Tstring"
  | Tsignature -> "Tsignature"
  | Tobject_path -> "Tobject_path"

let print_tbasic pp t = pp_print_string pp (string_of_tbasic t)

let rec print_tsingle pp = function
  | Tbasic t -> fprintf pp "@[<2>Tbasic@ %a@]" print_tbasic t
  | Tarray t -> fprintf pp "@[<2>Tarray@,(%a)@]" print_tsingle t
  | Tdict(tk, tv) -> fprintf pp "@[<2>Tdict@,(@[<hv>%a,@ %a@])@]" print_tbasic tk print_tsingle tv
  | Tstructure tl -> fprintf pp "@[<2>Tstructure@ %a@]" print_tsequence tl
  | Tvariant -> fprintf pp "Tvariant"

and print_tsequence pp = print_list print_tsingle pp

(* +----------------------+
   | Signature validation |
   +----------------------+ *)

let validate_signature =
  let rec aux_single depth_struct depth_array depth_dict_entry = function
    | Tbasic _ | Tvariant ->
        None
    | Tarray t ->
        if depth_array > Constant.max_type_recursion_depth then
          Some "too many nested arrays"
        else
          aux_single depth_struct (depth_array + 1) depth_dict_entry t
    | Tdict(tk, tv) ->
        if depth_array > Constant.max_type_recursion_depth then
          Some "too many nested arrays"
        else if depth_dict_entry > Constant.max_type_recursion_depth then
          Some "too many nested dict-entries"
        else
          aux_single depth_struct (depth_array + 1) (depth_dict_entry + 1) tv
    | Tstructure [] ->
        Some "empty structure"
    | Tstructure tl ->
        if depth_struct > Constant.max_type_recursion_depth then
          Some "too many nested structures"
        else
          aux_sequence (depth_struct + 1) depth_array depth_dict_entry tl

  and aux_sequence depth_struct depth_array depth_dict_entry = function
    | [] ->
        None
    | t :: tl ->
        match aux_single depth_struct depth_array depth_dict_entry t with
          | None ->
              aux_sequence depth_struct depth_array depth_dict_entry tl
          | error ->
              error
  in
  aux_sequence 0 0 0

(* +-------------------+
   | Signature reading |
   +-------------------+ *)

module type Char_reader = sig
  type 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val return : 'a -> 'a t
  val failwith : string -> 'a t

  val get_char : char t
  val eof : bool t
end

module Make_signature_reader(Reader : Char_reader) =
struct
  open Reader

  let ( >>= ) = bind

  let parse_basic msg = function
    | 'y' -> return Tbyte
    | 'b' -> return Tboolean
    | 'n' -> return Tint16
    | 'q' -> return Tuint16
    | 'i' -> return Tint32
    | 'u' -> return Tuint32
    | 'x' -> return Tint64
    | 't' -> return Tuint64
    | 'd' -> return Tdouble
    | 's' -> return Tstring
    | 'o' -> return Tobject_path
    | 'g' -> return Tsignature
    | chr -> Printf.ksprintf failwith msg chr

  let rec parse_single = function
    | 'a' ->
        begin
          get_char >>= function
            | '{' ->
                (perform
                   tk <-- get_char >>= parse_basic "invalid basic type code: %c";
                   tv <-- get_char >>= parse_single;
                   get_char >>= function
                     | '}' -> return (Tdict(tk, tv))
                     | _ -> failwith "'}' missing")
            | ch ->
                (perform
                   t <-- parse_single ch;
                   return (Tarray t))
        end
    | '(' ->
        (perform
           t <-- get_char >>= parse_struct;
           return (Tstructure t))
    | ')' ->
        failwith "')' without '('"
    | 'v' ->
        return Tvariant
    | ch ->
        (perform
           t <-- parse_basic "invalid type code: %c" ch;
           return (Tbasic t))

  and parse_struct = function
    | ')' ->
        return []
    | ch ->
        (perform
           t <-- parse_single ch;
           l <-- get_char >>= parse_struct;
           return (t :: l))

  let rec parse_sequence = function
    | true ->
        return []
    | false ->
        (perform
           t <-- get_char >>= parse_single;
           l <-- eof >>= parse_sequence;
           return (t :: l))

  let read_signature = eof >>= parse_sequence
end

(* +-------------------+
   | Signature writing |
   +-------------------+ *)

module type Char_writer = sig
  type 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val return : 'a -> 'a t

  val put_char : char -> unit t
end

let basic_type_code = function
  | Tbyte -> 'y'
  | Tboolean -> 'b'
  | Tint16 -> 'n'
  | Tuint16 -> 'q'
  | Tint32 -> 'i'
  | Tuint32 -> 'u'
  | Tint64 -> 'x'
  | Tuint64 -> 't'
  | Tdouble -> 'd'
  | Tstring -> 's'
  | Tobject_path -> 'o'
  | Tsignature -> 'g'

module Make_signature_writer(Writer : Char_writer) =
struct
  open Writer

  let ( >>= ) = bind

  let rec write_single = function
    | Tbasic t ->
        (1, put_char (basic_type_code t))
    | Tarray t ->
        let sz, wr = write_single t in
        (sz + 1, perform put_char 'a'; wr)
    | Tdict(tk, tv) ->
        let sz, wr = write_single tv in
        (sz + 4,
         perform
           put_char 'a';
           put_char '{';
           put_char (basic_type_code tk);
           wr;
           put_char '}')
    | Tstructure ts ->
        let sz, wr = write_sequence ts in
        (sz + 2, perform put_char '('; wr; put_char ')')
    | Tvariant ->
        (1, put_char 'v')

  and write_sequence = function
    | [] ->
        0, return ()
    | x :: l ->
        let shd, whd = write_single x
        and stl, wtl = write_sequence l in
        (shd + stl, perform whd; wtl)

  let write_signature = write_sequence
end

(* +----------------------+
   | signature <-> string |
   +----------------------+ *)

type ptr = { buffer : string; mutable offset : int }

module Ptr =
struct
  type 'a t = ptr -> 'a
  let bind m f ptr = f (m ptr) ptr
  let return x _ = x
end

module Signature_reader = Make_signature_reader
  (struct
     include Ptr
     let failwith msg _ = Pervasives.failwith msg
     let get_char ptr =
       let n = ptr.offset in
       if n = String.length ptr.buffer then
         Pervasives.failwith "premature end of signature"
       else begin
         ptr.offset <- n + 1;
         String.unsafe_get ptr.buffer n
       end
     let eof ptr = ptr.offset = String.length ptr.buffer
   end)

module Signature_writer = Make_signature_writer
  (struct
     include Ptr
     let put_char ch ptr =
       let n = ptr.offset in
       (* The size of the signature is computed before so there is
          always enough room *)
       String.unsafe_set ptr.buffer n ch;
       ptr.offset <- n + 1
   end)

let string_of_signature ts =
  let len, writer = Signature_writer.write_signature ts in
  let str = String.create len in
  writer { buffer = str; offset = 0 };
  str

let signature_of_string str =
  try
    Signature_reader.read_signature { buffer = str; offset = 0 }
  with
      Failure msg ->
        raise (Invalid_argument
                 (sprintf "signature_of_string: invalid signature(%S): %s" str msg))

(* +------------------------+
   | DBus value definitions |
   +------------------------+ *)

type basic =
  | Byte of char
  | Boolean of bool
  | Int16 of int
  | Int32 of int32
  | Int64 of int64
  | Uint16 of int
  | Uint32 of int32
  | Uint64 of int64
  | Double of float
  | String of string
  | Signature of signature
  | Object_path of OBus_path.t
 with constructor

type single =
  | Basic of basic
  | Array of tsingle * single list
  | Dict of tbasic * tsingle * (basic * single) list
  | Structure of single list
  | Variant of single
 with constructor

type sequence = single list

let sbyte x = Basic(Byte x)
let sboolean x = Basic(Boolean x)
let sint16 x = Basic(Int16 x)
let sint32 x = Basic(Int32 x)
let sint64 x = Basic(Int64 x)
let suint16 x = Basic(Uint16 x)
let suint32 x = Basic(Uint32 x)
let suint64 x = Basic(Uint64 x)
let sdouble x = Basic(Double x)
let sstring x = Basic(String x)
let ssignature x = Basic(Signature x)
let sobject_path x = Basic(Object_path x)

(* +--------------+
   | Value typing |
   +--------------+ *)

let type_of_basic = function
  | Byte _ -> Tbyte
  | Boolean _ -> Tboolean
  | Int16 _ -> Tint16
  | Int32 _ -> Tint32
  | Int64 _ -> Tint64
  | Uint16 _ -> Tuint16
  | Uint32 _ -> Tuint32
  | Uint64 _ -> Tuint64
  | Double _ -> Tdouble
  | String _ -> Tstring
  | Signature _ -> Tsignature
  | Object_path _ -> Tobject_path

let rec type_of_single = function
  | Basic x -> Tbasic(type_of_basic x)
  | Array(t, x) -> Tarray t
  | Dict(tk, tv, x) -> Tdict(tk, tv)
  | Structure x -> Tstructure(List.map type_of_single x)
  | Variant _ -> Tvariant

let type_of_sequence = List.map type_of_single

let array t l =
  List.iter (fun x ->
               if type_of_single x <> t then
                 invalid_arg "OBus_value.array: unexpected type") l;
  Array(t, l)

let dict tk tv l =
  List.iter (fun (k, v) ->
               if type_of_basic k <> tk || type_of_single v <> tv then
                 invalid_arg "OBus_value.dict: unexpected type") l;
  Dict(tk, tv, l)

(* +-----------------------+
   | Value pretty-printing |
   +-----------------------+ *)

let print_basic pp = function
  | Byte x -> fprintf pp  "%C" x
  | Boolean x -> fprintf pp "%B" x
  | Int16 x -> fprintf pp "%d" x
  | Int32 x -> fprintf pp "%ldl" x
  | Int64 x -> fprintf pp "%LdL" x
  | Uint16 x -> fprintf pp "%d" x
  | Uint32 x -> fprintf pp "%ldl" x
  | Uint64 x -> fprintf pp "%LdL" x
  | Double x -> fprintf pp "%f" x
  | String x -> fprintf pp "%S" x
  | Signature x -> print_tsequence pp x
  | Object_path x -> print_list (fun pp elt -> fprintf pp "%S" elt) pp x

let rec print_single pp = function
  | Basic v -> print_basic pp v
  | Array(t, l) -> print_list print_single pp l
  | Dict(tk, tv, l) -> print_list (fun pp (k, v) -> fprintf pp "(@[%a,@ %a@])" print_basic k print_single v) pp l
  | Structure l -> print_sequence pp l
  | Variant x -> fprintf pp "@[<2>Variant@,(@[<hv>%a,@ %a@])@]" print_tsingle (type_of_single x) print_single x

and print_sequence pp l = print_tuple print_single pp l

let string_of_tsingle = string_of print_tsingle
let string_of_tsequence = string_of print_tsequence
let string_of_basic = string_of print_basic
let string_of_single = string_of print_single
let string_of_sequence = string_of print_sequence
