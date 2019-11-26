module Main exposing (main)

import Browser
import Html exposing (Html, text, pre, ul, li, table, tr, td, th)
import Http
import Json.Decode exposing (Decoder, field, int, map3, maybe, oneOf, list, string, succeed)

-- MAIN

main =
  Browser.element
    { init = init
    , update = update
    , subscriptions = subscriptions
    , view = view
    }

-- MODEL

type Model
  = Failure String
  | Loading
  | Success (List Destination)


init : () -> (Model, Cmd Msg)
init _ =
  ( Loading
  , Http.get
      { url = "http://localhost:8000/spamstats.json"
      , expect = Http.expectJson GotText destinationsDecoder
      }
  )


-- UPDATE

type Msg
  = GotText (Result Http.Error (List Destination))


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    GotText result ->
      case result of
        Ok destinations ->
          (Success destinations, Cmd.none)
        
        Err err ->
          case err of
            Http.BadBody str ->
              (Failure str, Cmd.none)
            Http.NetworkError ->
              (Failure "network error", Cmd.none)
            _ ->
              (Failure "unknown", Cmd.none)

-- SUBSCRIPTIONS
subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none

-- VIEW

destinationRowView : Destination -> Html Msg
destinationRowView d =
  tr []
    [ td [] [ text d.email ]
    , td [] [ text (String.fromInt d.spam ) ]
    , td [] [ text (String.fromInt d.ham ) ]
    ]

destinationsTableView : List (Html Msg) -> Html Msg
destinationsTableView dsts =
  dsts
    |> (++)
      [ tr []
        [ th [] [ text "Email" ]
        , th [] [ text "Spam" ]
        , th [] [ text "Ham" ]
        ]
      ]
    |> table []

view : Model -> Html Msg
view model =
  case model of
    Failure err ->
      text ("Something went wrong when loading :(. Got error: " ++ err)
    
    Loading ->
      text "Fetching stats"
    
    Success destinations ->
      destinations
        |> List.sortBy .spam
        |> List.reverse
        |> List.map destinationRowView
        |> destinationsTableView


-- HTTP

type alias Destination =
  { email: String
  , spam: Int
  , ham: Int
  }

destinationDecoder: Decoder Destination
destinationDecoder =
  map3 Destination
    (field "email" string)
    (oneOf [(field "spam" int), succeed 0 ])
    (oneOf [(field "ham" int), succeed 0 ])

destinationsDecoder: Decoder (List Destination)
destinationsDecoder =
  field "destinations" (list destinationDecoder)