open Lwt
open Comics_provider
open Cohttp
open Cohttp_lwt
open Cohttp_lwt_unix
open Xkcd_provider
open Sqlite3

module Json = Yojson.Basic

let map_inline_result result =
  let uri = Uri.to_string result.Comics_provider.uri 
  and reference = Uri.to_string result.Comics_provider.reference in
  let caption = Format.sprintf "[%s (%s)](%s)" result.title result.Comics_provider.id reference in
  `Assoc [
    ("type", `String "photo");
    ("id", `String result.Comics_provider.id);
    ("photo_url", `String uri);
    ("thumb_url", `String uri);
    ("caption", `String caption);
    ("photo_width", `Int result.Comics_provider.width);
    ("photo_height", `Int result.Comics_provider.height);
    ("parse_mode", `String "Markdown")
  ]

(* Prepares the body to POST to "answerInlineQuery" *)
let encode_inline_reply_body id results =
  results
  |> List.map map_inline_result
  |> (fun results -> `Assoc [("inline_query_id", `String id); ("results", `List results)])
  |> Json.to_string
  |> Body.of_string

(* Answers the inline query *)
let inline_reply id results =
  let body = encode_inline_reply_body id results in
  let headers = Header.of_list [("Content-Type", "application/json")] in
  let token = Sys.getenv "TELEGRAM_BOT_TOKEN" in
  let path = Format.sprintf "bot%s/answerInlineQuery" token in
  let uri = Uri.make ~scheme:"https" ~host:"api.telegram.org" ~path:path () in
  Client.post ~headers:headers ~body:body uri

(* Decodes Telegram "update" requests into a (inline query id, query text) pair *)
let decode_update body =
  wrap (fun () ->
    let json = body |> Json.from_string in
    let inline_query = json |> Json.Util.member "inline_query" in
    let id = inline_query |> Json.Util.member "id" |> Json.Util.to_string in
    let query = inline_query |> Json.Util.member "query" |> Json.Util.to_string in
    (id, query))

(* Trims the search query and fails if the resulting string is empty *)
let cleanup_query query =
  wrap (fun () ->
    match String.trim query with
    | query when String.length query > 0 -> query
    | _ -> raise (Invalid_argument "query"))

(* Handles the inline query *)
let handle_inline_query provider db (id, inline_query) =
  Lwt.async (fun () -> Lwt_io.printf "%f: %s\n" (Unix.time ()) inline_query);
  let module Provider = (val provider: ComicsProvider) in
  catch
    (fun () ->
       cleanup_query inline_query
       >>= wrap1 (Provider.search_matching db)
       >>= inline_reply id)
    (fun (_) ->
       inline_reply id [])

(* Handles HTTP requests *)
let handle_request provider db body =
  catch
    (fun () ->
       Body.to_string body
       >>= decode_update
       >>= handle_inline_query provider db
       >>= (fun (_) -> Server.respond_string ~status:`OK ~body:"" ()))
    (fun (_) -> Server.respond_string ~status:`No_content ~body:"" ())

(* Maps requests into comic modules *)
let comic_provider t = match t with
  | "xkcd" -> (module XkcdProvider: ComicsProvider)
  | _ -> failwith "Unknown comics provider"

(* Opens the sqlite database and creates an HTTP server to receive Telegram updates *)
let create_server db_path provider_name =
  let provider = comic_provider provider_name
  and db = db_open db_path in
  let request_callback _conn _req body = handle_request provider db body in
  Server.create ~mode:(`TCP (`Port 8000)) (Server.make ~callback:request_callback ())

(* Parses command line arguments and runs the server thread *)
let () =
  match Sys.argv with
  | args when Array.length args > 2 -> create_server args.(1) args.(2) |> Lwt_main.run |> ignore
  | _ -> failwith "Not enough arguments"
