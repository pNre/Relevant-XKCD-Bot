open Comics_indexer
open Lwt
open Cohttp_lwt
open Cohttp_lwt_unix
open Format
open Images
open Sqlite3

module Json = Yojson.Basic

module XkcdIndexer: ComicsIndexer = struct
  let get_comic_at uri =
    Client.get uri
    >>= fun (_, body) -> Body.to_string body
    >>= fun body -> wrap (fun () -> Json.from_string body)

  let get_last_comic_id =
    let uri = Uri.of_string "https://xkcd.com/info.0.json" in
    get_comic_at uri
    >|= fun json -> 
      json 
      |> Json.Util.member "num" 
      |> Json.Util.to_int

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
    let parse () = 
      let id = json |> Json.Util.member "num" |> Json.Util.to_int
      and title = json |> Json.Util.member "safe_title" |> Json.Util.to_string
      and alt = json |> Json.Util.member "alt" |> Json.Util.to_string
      and img = json |> Json.Util.member "img" |> Json.Util.to_string in
      (id, title, alt, img) 
    and download (id, title, alt, img) =
      let uri = Uri.of_string img in
      size_of_image_at_uri uri
      >|= fun (w, h) -> 
        (id, title, alt, img, w, h) in
    wrap parse
    >>= download

  let save_comic db (id, title, alt, img, w, h) =
    wrap (fun () ->
      let statement = prepare db "INSERT INTO xkcd (id, alt, title, uri, w, h) VALUES (?, ?, ?, ?, ?, ?)" in
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

  let rec index db progress_cb current last =
    match current > last with
    | true -> return_unit
    | false ->
      Lwt.async (fun () -> progress_cb current last);
      Lwt_unix.sleep 0.25
      >>= fun () -> get_and_save_comic db current
      >>= fun () -> index db progress_cb (current + 1) last

  let get_last_downloaded_comic_id db =
    let statement = prepare db "SELECT IFNULL(MAX(id), 1) FROM xkcd" in
    match step statement with
    | Rc.ROW ->
      let row = row_data statement in
      row.(0)
      |> Data.to_string
      |> int_of_string
    | _ -> 1

  let index_comics db progress_cb =
    let first = get_last_downloaded_comic_id db in
    get_last_comic_id
    >>= fun last -> index db progress_cb first last
    >|= fun _ -> ()
end
