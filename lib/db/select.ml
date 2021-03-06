
open Lib_common
open Lib_model
open Lwt.Infix
open Printf
open Util

exception ID_not_int

let first_row_of_result res =
  stream res >>= stream_next_opt >>= Lwt.return

let id_of_first_row result =
  let exception ID_not_int in
  first_row_of_result result >>= function
  | None -> Lwt.return_none
  | Some row ->
    match row |> Mdb.Row.StringMap.find "id" |> Mdb.Field.value with
    | `Int id -> Lwt.return_some id
    | _ -> Lwt.fail ID_not_int


let id_of_alias db_connect name =
  let query = "SELECT id FROM alias WHERE name = ? ORDER BY id ASC LIMIT 1" in
  let values = [| `String name |] in
  execute db_connect query values id_of_first_row

let id_of_url db_connect url = 
  let values = values_of_url url |> Array.to_list in
  let where = List.combine url_fields values
    |> List.map (function 
      | (field, `Null) -> field ^ " IS NULL"
      | (field,     _) -> field ^ " = ?")
    |> String.concat " AND "
  in
  let values' = values |> List.filter (function `Null -> false | _ -> true) in

  let query = 
    "SELECT id FROM url WHERE " ^ where ^ " ORDER BY id ASC LIMIT 1"
  in 
  execute db_connect query (Array.of_list values') id_of_first_row

let alias_of_row row = Alias.({
  id = Some (int_of_map row "id" |> ID.of_int);
  name = string_of_map row "name" |> Name.of_string;
  url = Url.ID (int_of_map row "url" |> Url.ID.of_int);
  status = string_of_map row "status" |> Status.of_string;
})

let alias_by_name db_connect name =
  let fields = ("id" :: alias_fields) |> String.concat ", " in
  let query = "SELECT " ^ fields ^ " FROM alias "
            ^ "WHERE name = ? LIMIT 1" in
  execute db_connect query [| `String name |] (first_row_of_result)
  >>= function
  | None -> Lwt.return_none
  | Some row -> Lwt.return_some (alias_of_row row)


let aliases_of_url db_connect url_id =
  let fields = ("id" :: alias_fields) |> String.concat ", " in
  let query = "SELECT " ^ fields ^ " FROM alias "
            ^  "WHERE url = ? ORDER BY name ASC" in
  let values = Alias.([| `Int url_id; |]) in

  execute db_connect query values (fun result ->
    stream result >>= 
    Lwt_stream.map (alias_of_row) %> 
    Lwt_stream.to_list >>= 
    Lwt.return
  )

let url_of_row row = Url.({
  id = maybe_int_of_map row "id" (ID.of_int);
  scheme = string_of_map row "scheme" |> Scheme.of_string;
  user = maybe_string_of_map row "user" (Username.of_string);
  password = maybe_string_of_map row "password" (Password.of_string);
  host = string_of_map row "host" |> Host.of_string;
  port = maybe_int_of_map row "port" (Port.of_int);
  path = string_of_map row "path" |> Path.of_string;
  params = maybe_string_of_map row "params" (Params.of_string);
  fragment = maybe_string_of_map row "fragment" (Fragment.of_string);
})

let url_of_first_row result = 
  first_row_of_result result >>= function 
  | None -> Lwt.return_none
  | Some row -> Lwt.return_some @@ url_of_row row

let url_by_id db_connect id =
  let fields = ("id" :: url_fields) |> String.concat ", " in
  let query = "SELECT " ^ fields ^ " FROM url WHERE id = ? "
            ^ "ORDER BY id ASC LIMIT 1" in
  execute db_connect query [| `Int id |] url_of_first_row

let url_of_alias db_connect name =
  let fields = "id" :: url_fields in
  let select = fields
    |> List.map (fun f -> "url." ^ f ^ " AS " ^ f)
    |> String.concat ", " in
  let query = 
    "SELECT " ^ select ^ " FROM alias "
     ^ "JOIN url ON url.id = alias.url "
     ^ "WHERE alias.name = ? "
     ^ "ORDER BY url.id LIMIT 1" in

  execute db_connect query [| `String name |] url_of_first_row

let count_of_first_row result =
  let exception Count_not_int in
  first_row_of_result result >>= function
  | None -> Lwt.return 0
  | Some row ->
    match row |> Mdb.Row.StringMap.find "count" |> Mdb.Field.value with
    | `Int count -> Lwt.return count
    | _ -> Lwt.fail Count_not_int

let use_count_of_alias db_connect name =
  let query = "SELECT COUNT(u.id) AS count FROM `use` AS u "
            ^ "JOIN alias ON alias.id = u.alias "
            ^ "WHERE alias.name = ?" in
  execute db_connect query [| `String name |] count_of_first_row