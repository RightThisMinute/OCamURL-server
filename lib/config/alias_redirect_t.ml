(* Auto-generated from "alias_redirect.atd" *)


type database = Database_t.t

type t = {
  port: int;
  database: database;
  pathless_redirect_uri: string option
}