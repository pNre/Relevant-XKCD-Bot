open Lwt
open Cohttp
open Cohttp_lwt
open Cohttp_lwt_unix
open Yojson.Basic
open Sqlite3

let map_inline_result (id, title, url, w, h) =
  `Assoc [
    ("type", `String "photo");
    ("id", `String id);
    ("photo_url", `String url);
    ("thumb_url", `String url);
    ("caption", `String (Format.sprintf "%s (%s)" title id));
    ("photo_width", `Int (int_of_string w));
    ("photo_height", `Int (int_of_string h))
  ]

(* Prepares the body to POST to "answerInlineQuery" *)
let encode_inline_reply_body id results =
  results
  |> List.map map_inline_result
  |> (fun results -> `Assoc [("inline_query_id", `String id); ("results", `List results)])
  |> to_string
  |> Body.of_string

(* Answers the inline query *)
let inline_reply (id, results) =
  let body = encode_inline_reply_body id results in
  let headers = Header.of_list [("Content-Type", "application/json")] in
  let token = Sys.getenv "TELEGRAM_BOT_TOKEN" in
  let path = Format.sprintf "bot%s/answerInlineQuery" token in
  let uri = Uri.make ~scheme:"https" ~host:"api.telegram.org" ~path:path () in
  Client.post ~headers:headers ~body:body uri

(* Gets the rows in db that match inline_query *)
let search_matching_comic_for_inline_query db id inline_query =
  wrap (fun () ->
    let statement = prepare db "
        SELECT id, title, img, w, h
        FROM comic
        WHERE id = ?
           OR title LIKE ? COLLATE NOCASE
           OR alt LIKE ? COLLATE NOCASE" in
    let _ = bind statement 1 (TEXT inline_query) in
    let _ = bind statement 2 (TEXT (Format.sprintf "%%%s%%" inline_query)) in
    let _ = bind statement 3 (TEXT (Format.sprintf "%%%s%%" inline_query)) in
    let rec stepper results =
      match step statement with
      | Rc.ROW ->
        let row = row_data statement in
        let id = Data.to_string row.(0) in
        let title = Data.to_string row.(1) in
        let img = Data.to_string row.(2) in
        let w = Data.to_string row.(3) in
        let h = Data.to_string row.(4) in
        stepper ((id, title, img, w, h) :: results)
      | _ -> results in
    (id, stepper []))

  (* Decodes Telegram "update" requests into a (inline query id, query text) pair *)
let decode_update body =
  wrap (fun () ->
    let json = body |> from_string in
    let inline_query = json |> Util.member "inline_query" in
    let id = inline_query |> Util.member "id" |> Util.to_string in
    let query = inline_query |> Util.member "query" |> Util.to_string in
    (id, query))

(* Handles the inline query *)
let handle_inline_query db (id, inline_query) =
  Lwt.async (fun () -> Lwt_io.printf "Q: %s\n" inline_query);
  catch
    (fun () ->
      search_matching_comic_for_inline_query db id inline_query
      >>= inline_reply)
    (fun (_) -> 
      inline_reply (id, []))

(* Handles HTTP requests *)
let handle_request db body =
  catch
    (fun () ->
      Body.to_string body
      >>= decode_update
      >>= handle_inline_query db
      >>= (fun (_) -> Server.respond_string ~status:`OK ~body:"" ()))
    (fun (_) -> Server.respond_string ~status:`No_content ~body:"" ())

(* Opens the sqlite database and creates an HTTP server to receive Telegram updates *)
let create_server db_path =
  let db = db_open db_path in
  let request_callback _conn _req body = handle_request db body in
  Server.create ~mode:(`TCP (`Port 8000)) (Server.make ~callback:request_callback ())

(* Parses command line arguments and runs the server thread *)
let () =
  match Sys.argv with
  | args when Array.length args > 1 -> create_server args.(1) |> Lwt_main.run |> ignore
  | _ -> failwith "Not enough arguments"
