module Main exposing (main)

import Browser
import Html exposing (Html, div, text, pre, ul, li, table, tr, td, th)
import Http
import Json.Decode exposing (Decoder, field, int, map2, map3, map6, maybe, oneOf, list, string, succeed)
import Round

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
  | Success Stats


init : () -> (Model, Cmd Msg)
init _ =
  ( Loading
  , Http.get
      { url = "http://localhost:8000/spamstats.json"
      , expect = Http.expectJson GotText statsDecoder
      }
  )


-- UPDATE

type Msg
  = GotText (Result Http.Error Stats)


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    GotText result ->
      case result of
        Ok stats ->
          (Success stats, Cmd.none)
        
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

yearMonthRowView : YearMonth -> Html Msg
yearMonthRowView ym =
  tr []
    [ td [] [ text ym.yearMonth ]
    , td [] [ text (String.fromInt ym.sge ) ]
    , td [] [ text (String.fromInt ym.hlt ) ]
    , td [] [ text (String.fromInt ym.hge ) ]
    , td [] [ text (String.fromInt ym.slt ) ]
    , td [] [ text (String.fromInt ym.discarded ) ]
    , td [] [ text (Round.round 2 (toFloat ym.slt / toFloat (ym.slt + ym.sge) * 100) ++ " %") ]
    , td [] [ text (Round.round 2 (toFloat ym.discarded / toFloat (ym.sge + ym.slt) * 100) ++ " %") ]
    ]

yearMonthsTableView : List (Html Msg) -> Html Msg
yearMonthsTableView dsts =
  dsts
    |> (++)
      [ tr []
        [ th [] []
        , th [] [ text "True positive" ]
        , th [] [ text "True negative" ]
        , th [] [ text "False positive" ]
        , th [] [ text "True positive" ]
        , th [] [ text "Discarded" ]
        , th [] [ text "FNR" ]
        , th [] [ text "Discard rate" ]
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
    
    Success stats ->
      div []
        [ stats.destinations
            |> List.sortBy .spam
            |> List.reverse
            |> List.map destinationRowView
            |> destinationsTableView
        , stats.yearmonths
            |> List.sortBy .yearMonth
            |> List.map yearMonthRowView
            |> yearMonthsTableView
        ]


-- HTTP

type alias Stats =
  { yearmonths: List YearMonth
  , destinations: List Destination
  }

statsDecoder: Decoder Stats
statsDecoder =
  map2 Stats
    yearMonthsDecoder
    destinationsDecoder


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

type alias YearMonth =
  { yearMonth: String
  , slt: Int  -- false negative
  , sge: Int  -- true positive
  , hlt: Int  -- true negative
  , hge: Int  -- false negative
  , discarded: Int
  }

yearMonthDecoder: Decoder YearMonth
yearMonthDecoder =
  map6 YearMonth
    (field "yearmonth" string)
    (field "slt" int)
    (field "sge" int)
    (field "hlt" int)
    (field "hge" int)
    (field "discarded" int)

yearMonthsDecoder: Decoder (List YearMonth)
yearMonthsDecoder =
  field "yearmonths" (list yearMonthDecoder)

