module Main exposing (main)

import Bootstrap.CDN as CDN
import Bootstrap.Grid as Grid
import Bootstrap.Table as Table
import Browser
import Html exposing (Html, div, text, pre, ul, li, table, tr, td, th)
import Html.Attributes
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

tableStyle = [ Table.striped, Table.hover, Table.small ]

rightAlign = Table.cellAttr <| Html.Attributes.style "text-align" "right"

formatPercentage : Int -> Int -> String
formatPercentage num denom = (Round.round 2 (toFloat num / toFloat denom * 100) ++ "\u{00A0}%")


destinationRowView : Destination -> Table.Row Msg
destinationRowView d =
  Table.tr []
    [ Table.td [] [ text d.email ]
    , Table.td [ rightAlign ] [ text (String.fromInt d.spam ) ]
    , Table.td [ rightAlign ] [ text (String.fromInt d.ham ) ]
    ]

destinationsTableView : List (Table.Row Msg) -> Html Msg
destinationsTableView dsts =
  Table.table
    { options = tableStyle
    , thead = Table.simpleThead
        [ Table.th [] [ text "Email" ]
        , Table.th [ rightAlign ] [ text "Spam" ]
        , Table.th [ rightAlign ] [ text "Ham" ]
        ]
    , tbody = Table.tbody [] dsts
    }

yearMonthRowView : YearMonth -> Table.Row Msg
yearMonthRowView ym =
  Table.tr []
    [ Table.td [] [ text ym.yearMonth ]
    , Table.td [ rightAlign ] [ text <| String.fromInt ym.hlt ]
    , Table.td [ rightAlign ] [ text <| String.fromInt ym.hge ]
    , Table.td [ rightAlign ] [ text <| String.fromInt ym.slt ]
    , Table.td [ rightAlign ] [ text <| String.fromInt ym.sge ]
    , Table.td [ rightAlign ] [ text <| String.fromInt ym.discarded ]
    , Table.td [ rightAlign ] [ text <| formatPercentage ym.slt (ym.slt + ym.sge) ]
    , Table.td [ rightAlign ] [ text <| formatPercentage ym.discarded (ym.sge + ym.slt) ]
    ]

yearMonthsTableView : List (Table.Row Msg) -> Html Msg
yearMonthsTableView dsts =
  Table.table
    { options = tableStyle
    , thead = Table.simpleThead
        [ Table.th [] []
        , Table.th [ rightAlign ] [ text "True negative" ]
        , Table.th [ rightAlign ] [ text "False positive" ]
        , Table.th [ rightAlign ] [ text "False negative" ]
        , Table.th [ rightAlign ] [ text "True positive" ]
        , Table.th [ rightAlign ] [ text "Discarded" ]
        , Table.th [ rightAlign ] [ text "FNR" ]
        , Table.th [ rightAlign ] [ text "Discard rate" ]
        ]
    , tbody = Table.tbody [] dsts
    }

view : Model -> Html Msg
view model =
  Grid.container []
    [ CDN.stylesheet
    , case model of
      Failure err ->
        text ("Something went wrong when loading :(. Got error: " ++ err)
      
      Loading ->
        text "Fetching stats"
      
      Success stats ->
        Grid.row []
          [Grid.col []
            [ stats.destinations
                |> List.sortBy .spam
                |> List.reverse
                |> List.map destinationRowView
                |> destinationsTableView
            ]
          , Grid.col []
            [ stats.yearmonths
                |> List.sortBy .yearMonth
                |> List.map yearMonthRowView
                |> yearMonthsTableView
            ]
          ]
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

