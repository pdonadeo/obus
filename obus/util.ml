(*
 * util.ml
 * -------
 * Copyright : (c) 2008, Jeremie Dimino <jeremie@dimino.org>
 * Licence   : BSD3
 *
 * This file is a part of obus, an ocaml implemtation of dbus.
 *)

let rec assoc x = function
  | [] -> None
  | (k, v) :: _ when k = x -> Some(v)
  | _ :: l -> assoc x l

let rec find_map f = function
  | [] -> None
  | x :: l -> match f x with
      | None -> find_map f l
      | y -> y

let filter_map f l =
  List.fold_right (fun x acc -> match f x with
                    | None -> acc
                    | Some(v) -> v :: acc) l []

let part_map f l =
  List.fold_right (fun x (success, failure) -> match f x with
                     | None -> (success, x :: failure)
                     | Some(v) -> (v :: success, failure)) l ([], [])

let try_finally f close arg =
  let result =
    try
      f arg
    with
      | e ->
          close arg;
          raise e
  in
    close arg;
    result

type ('a, 'b) either =
  | Left of 'a
  | Right of 'b

let rec split f l =
  List.fold_right (fun x (a, b) -> match f x with
                     | Left x -> (x :: a, b)
                     | Right x -> (a, x :: b)) l ([], [])

let encode_char n =
  if n < 10 then
    char_of_int (n + Char.code '0')
  else if n < 16 then
    char_of_int (n + Char.code 'a' - 10)
  else
    assert false

let hex_encode str =
  let len = String.length str in
  let hex = String.create (len * 2) in
  for i = 0 to len - 1 do
    let n = Char.code (String.unsafe_get str i) in
    String.unsafe_set hex (i * 2) (encode_char (n lsr 4));
    String.unsafe_set hex (i * 2 + 1) (encode_char (n land 15))
  done;
  hex

let decode_char ch = match ch with
  | '0'..'9' -> Char.code ch - Char.code '0'
  | 'a'..'f' -> Char.code ch - Char.code 'a' + 10
  | 'A'..'F' -> Char.code ch - Char.code 'A' + 10
  | _ -> raise (Invalid_argument "Util.decode_char")

let hex_decode hex =
  if String.length hex mod 2 <> 0 then raise (Invalid_argument "Util.hex_decode");
  let len = String.length hex / 2 in
  let str = String.create len in
  for i = 0 to len - 1 do
    String.unsafe_set str i
      (char_of_int
         ((decode_char (String.unsafe_get hex (i * 2)) lsl 4) lor
            (decode_char (String.unsafe_get hex (i * 2 + 1)))))
  done;
  str

let with_open_in fname f =
  try_finally f close_in (open_in fname)

let with_open_out fname f =
  try_finally f close_out (open_out fname)

let with_process openp closep cmd f =
  let c = openp cmd in
  let result =
    try
      f c
    with
        exn ->
          ignore (closep c);
          raise exn
  in
  match closep c with
    | Unix.WEXITED 0 -> result
    | Unix.WEXITED n -> failwith (Printf.sprintf "command %S exited with status %d" cmd n)
    | Unix.WSIGNALED n -> failwith (Printf.sprintf "command %S killed by signal %d" cmd n)
    | Unix.WSTOPPED n -> failwith (Printf.sprintf "command %S stopped by signal %d" cmd n)

let with_process_in cmd = with_process Unix.open_process_in Unix.close_process_in cmd
let with_process_out cmd = with_process Unix.open_process_out Unix.close_process_out cmd

module type Monad = sig
  type 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val return : 'a -> 'a t
end

module Maybe =
struct
  type 'a t = 'a option
  let bind m f = match m with
    | Some v -> f v
    | None -> None
  let return v = Some v
  let failwith _ = None
  let wrap f m = bind m (fun x -> return (f x))
  let rec fold f l =
    List.fold_right (fun x acc ->
                       perform
                         x <-- f x;
                         l <-- acc;
                         return (x :: l)) l (return [])
end

module MaybeT(M : Monad) =
struct
  type 'a t = 'a option M.t
  let bind m f =
    M.bind m (function
                | Some v -> f v
                | None -> M.return None)
  let return v = M.return (Some v)
  let failwith _ = M.return None
  let wrap f m = bind m (fun x -> return (f x))
  let rec fold f l =
    List.fold_right (fun x acc ->
                       perform
                         x <-- f x;
                         l <-- acc;
                         return (x :: l)) l (return [])
end

let homedir = lazy((Unix.getpwuid (Unix.getuid ())).Unix.pw_dir)

let init_pseudo = Lazy.lazy_from_fun Random.self_init

let fill_pseudo buffer pos len =
  Lazy.force init_pseudo;
  for i = pos to pos + len - 1 do
    String.unsafe_set buffer i (char_of_int (Random.int 256))
  done

let fill_random buffer pos len =
  try
    with_open_in "/dev/urandom"
      (fun ic ->
         let n = input ic buffer pos len in
         if n < len then fill_pseudo buffer (pos + n) (len - n))
  with
      exn -> fill_pseudo buffer pos len

let gen_random n =
  let str = String.create n in
  fill_random str 0 n;
  str

(* Compute the sha1 of a string.

   Copied from uuidm by Daniel C. Bünzli, which can be found here:
   http://erratique.ch/software/uuidm *)
let sha_1 s =
  let sha_1_pad s =
    let len = String.length s in
    let blen = 8 * len in
    let rem = len mod 64 in
    let mlen = if rem > 55 then len + 128 - rem else len + 64 - rem in
    let m = String.create mlen in
    String.blit s 0 m 0 len;
    String.fill m len (mlen - len) '\x00';
    m.[len] <- '\x80';
    if Sys.word_size > 32 then begin
      m.[mlen - 8] <- Char.unsafe_chr (blen lsr 56 land 0xFF);
      m.[mlen - 7] <- Char.unsafe_chr (blen lsr 48 land 0xFF);
      m.[mlen - 6] <- Char.unsafe_chr (blen lsr 40 land 0xFF);
      m.[mlen - 5] <- Char.unsafe_chr (blen lsr 32 land 0xFF);
    end;
    m.[mlen - 4] <- Char.unsafe_chr (blen lsr 24 land 0xFF);
    m.[mlen - 3] <- Char.unsafe_chr (blen lsr 16 land 0xFF);
    m.[mlen - 2] <- Char.unsafe_chr (blen lsr 8 land 0xFF);
    m.[mlen - 1] <- Char.unsafe_chr (blen land 0xFF);
    m
  in
  (* Operations on int32 *)
  let ( &&& ) = ( land ) in
  let ( lor ) = Int32.logor in
  let ( lxor ) = Int32.logxor in
  let ( land ) = Int32.logand in
  let ( ++ ) = Int32.add in
  let lnot = Int32.lognot in
  let sr = Int32.shift_right in
  let sl = Int32.shift_left in
  let cls n x = (sl x n) lor (Int32.shift_right_logical x (32 - n)) in
  (* Start *)
  let m = sha_1_pad s in
  let w = Array.make 16 0l in
  let h0 = ref 0x67452301l in
  let h1 = ref 0xEFCDAB89l in
  let h2 = ref 0x98BADCFEl in
  let h3 = ref 0x10325476l in
  let h4 = ref 0xC3D2E1F0l in
  let a = ref 0l in
  let b = ref 0l in
  let c = ref 0l in
  let d = ref 0l in
  let e = ref 0l in
  for i = 0 to ((String.length m) / 64) - 1 do             (* For each block *)
    (* Fill w *)
    let base = i * 64 in
    for j = 0 to 15 do
      let k = base + (j * 4) in
      w.(j) <- sl (Int32.of_int (Char.code m.[k])) 24 lor
        sl (Int32.of_int (Char.code m.[k + 1])) 16 lor
        sl (Int32.of_int (Char.code m.[k + 2])) 8 lor
        (Int32.of_int (Char.code m.[k + 3]))
    done;
    (* Loop *)
    a := !h0; b := !h1; c := !h2; d := !h3; e := !h4;
    for t = 0 to 79 do
      let f, k =
        if t <= 19 then (!b land !c) lor ((lnot !b) land !d), 0x5A827999l else
          if t <= 39 then !b lxor !c lxor !d, 0x6ED9EBA1l else
            if t <= 59 then
	      (!b land !c) lor (!b land !d) lor (!c land !d), 0x8F1BBCDCl
	    else
              !b lxor !c lxor !d, 0xCA62C1D6l
      in
      let s = t &&& 0xF in
      if (t >= 16) then begin
	w.(s) <- cls 1 begin
	  w.((s + 13) &&& 0xF) lxor
	    w.((s + 8) &&& 0xF) lxor
	    w.((s + 2) &&& 0xF) lxor
	    w.(s)
	end
      end;
      let temp = (cls 5 !a) ++ f ++ !e ++ w.(s) ++ k in
      e := !d;
      d := !c;
      c := cls 30 !b;
      b := !a;
      a := temp;
    done;
    (* Update *)
    h0 := !h0 ++ !a;
    h1 := !h1 ++ !b;
    h2 := !h2 ++ !c;
    h3 := !h3 ++ !d;
    h4 := !h4 ++ !e
  done;
  let h = String.create 20 in
  let i2s h k i =
    h.[k] <- Char.unsafe_chr ((Int32.to_int (sr i 24)) &&& 0xFF);
    h.[k + 1] <- Char.unsafe_chr ((Int32.to_int (sr i 16)) &&& 0xFF);
    h.[k + 2] <- Char.unsafe_chr ((Int32.to_int (sr i 8)) &&& 0xFF);
    h.[k + 3] <- Char.unsafe_chr ((Int32.to_int i) &&& 0xFF);
  in
  i2s h 0 !h0;
  i2s h 4 !h1;
  i2s h 8 !h2;
  i2s h 12 !h3;
  i2s h 16 !h4;
  h
