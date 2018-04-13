open Lwt
open Cohttp_lwt
open Cohttp_lwt_unix
open Format
open Images
open Yojson.Basic
open Yojson.Basic.Util
open Sqlite3

let get_comic_at uri =
  Client.get uri
  >>= fun (_, body) -> Body.to_string body
  >>= fun body -> wrap (fun () -> from_string body)

let get_last_comic_id =
  let uri = Uri.of_string "https://xkcd.com/info.0.json" in
  get_comic_at uri
  >|= fun json -> json |> member "num" |> to_int

let get_comic_by_id id =
  id
  |> sprintf "https://xkcd.com/%d/info.0.json"
  |> Uri.of_string
  |> get_comic_at

let size_of_image_at_uri uri =
  let name = Filename.temp_file "xkcd" "" in
  Client.get uri
  >>= fun (_, body) ->
    Lwt_io.with_file ~mode:Lwt_io.output name (fun file ->
      Lwt_stream.iter_s (Lwt_io.write file) (Body.to_stream body))
  >|= fun (_) ->
    let (_, h) = file_format name in
    (h.header_width, h.header_height)

let parse_comic json =
  wrap (fun () ->
    let id = json |> member "num" |> to_int
    and title = json |> member "safe_title" |> to_string
    and alt = json |> member "alt" |> to_string
    and img = json |> member "img" |> to_string in
    (id, title, alt, img))
  >>= fun (id, title, alt, img) ->
    let uri = Uri.of_string img in
    size_of_image_at_uri uri
    >|= fun (w, h) ->
      (id, title, alt, img, w, h)

let save_comic db (id, title, alt, img, w, h) =
  wrap (fun () ->
    let statement = prepare db "INSERT INTO comic (id, alt, title, img, w, h) VALUES (?, ?, ?, ?, ?, ?)" in
    bind statement 1 (INT (Int64.of_int id)) |> ignore;
    bind statement 2 (TEXT alt) |> ignore;
    bind statement 3 (TEXT title) |> ignore;
    bind statement 4 (TEXT img) |> ignore;
    bind statement 5 (INT (Int64.of_int w)) |> ignore;
    bind statement 6 (INT (Int64.of_int h)) |> ignore;
    step statement |> ignore)

let get_and_save_comic db current =
  catch
    (fun () ->
      get_comic_by_id current
      >>= parse_comic
      >>= save_comic db
      >|= fun (_) -> ())
    (fun _ -> return_unit)

let rec crawl db current last =
  if current > last then
    Lwt_io.printf "Downloading done (%d of %d)\n" last last
  else
    Lwt_io.printf "Downloading %d of %d\n" current last
    >>= fun () -> Lwt_unix.sleep 0.25
    >>= fun () -> get_and_save_comic db current
    >>= fun () -> crawl db (current + 1) last

let get_last_downloaded_comic_id db =
  let statement = prepare db "SELECT IFNULL(MAX(id), 1) FROM comic" in
  match step statement with
  | Rc.ROW ->
    let row = row_data statement in
    row.(0)
    |> Data.to_string
    |> int_of_string
  | _ -> 1

let start_crawler db =
  let first = get_last_downloaded_comic_id db in
  get_last_comic_id
  >>= fun last -> crawl db first last

let () =
  match Sys.argv with
  | args when Array.length args > 1 -> 
    let db = db_open args.(1) in
    start_crawler db
    |> Lwt_main.run
    |> ignore
  | _ -> failwith "Not enough arguments"
