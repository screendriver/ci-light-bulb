module Main exposing (..)

import Bluetooth
import Dict exposing (Dict)
import Html exposing (Html, a, button, div, footer, img, p, text)
import Html.Attributes exposing (class, disabled, href, src, target, title)
import Http
import Json.Decode as Decode
import LightBulb exposing (lightBulb)
import Maybe.Extra
import RemoteData exposing (WebData)
import Time exposing (Time, second)
import Url exposing (Url, (</>), (<?>), (@), root, s, string, int, bool)


type alias Flags =
    { gitHubApiUrl : String
    , gitHubOwner : String
    , gitHubRepo : String
    , gitHubBranchBlacklist : String
    }


type alias BranchName =
    String


type alias BranchState =
    String


type alias Branches =
    Dict BranchName (WebData BranchState)


type alias State =
    { id : Int, state : String }


type alias GitHub =
    { apiUrl : String
    , owner : String
    , repo : String
    , branchBlacklist : List BranchName
    }


type alias Model =
    { gitHub : GitHub
    , bulbId : Maybe Bluetooth.BulbId
    , errorMessage : Maybe String
    , branches : WebData Branches
    }


type alias BluetoothError =
    String


type BulbColor
    = Off
    | Blue
    | Yellow
    | Green
    | Red
    | Pink


type alias RGB =
    ( Int, Int, Int )


type BulbMode
    = White
    | Colored


type Msg
    = Connect
    | ConnectionError BluetoothError
    | Connected Bluetooth.BulbId
    | Disconnect
    | Disconnected ()
    | FetchBranches Time
    | BranchesFetched (WebData (List BranchName))
    | StatusesFetched BranchName (WebData (List State))
    | ChangeBulbColor BulbColor
    | ValueWritten Bluetooth.WriteParams


bulbName : String
bulbName =
    "icolorlive"


service : String
service =
    "f000ffa0-0451-4000-b000-000000000000"


changeModeCharacteristic : String
changeModeCharacteristic =
    "f000ffa3-0451-4000-b000-000000000000"



-- 4d43 (0x4F43) changes to color
-- 4d57 (0x4F57) changes to white


changeColorCharacteristic : String
changeColorCharacteristic =
    "f000ffa4-0451-4000-b000-000000000000"


getRgb : BulbColor -> RGB
getRgb color =
    case color of
        Off ->
            ( 0, 0, 0 )

        Blue ->
            ( 0, 0, 26 )

        Yellow ->
            ( 26, 26, 0 )

        Green ->
            ( 0, 26, 0 )

        Red ->
            ( 26, 0, 0 )

        Pink ->
            ( 26, 0, 26 )


changeColor : BulbColor -> Cmd msg
changeColor color =
    getRgb color
        |> Bluetooth.WriteParams service changeColorCharacteristic
        |> Bluetooth.writeValue


decodeBranchNames : Decode.Decoder (List BranchName)
decodeBranchNames =
    Decode.list <|
        Decode.field "name" Decode.string


decodeStatuses : Decode.Decoder (List State)
decodeStatuses =
    Decode.list <|
        Decode.map2
            State
            (Decode.field "id" Decode.int)
            (Decode.field "state" Decode.string)


branchesUrl : Url { gitHubOwner : String, gitHubRepo : String }
branchesUrl =
    root
        </> s "repos"
        </> string .gitHubOwner
        </> string .gitHubRepo
        </> s "branches"


statusesUrl : Url { gitHubOwner : String, gitHubRepo : String, branchName : String }
statusesUrl =
    root
        </> s "repos"
        </> string .gitHubOwner
        </> string .gitHubRepo
        </> s "commits"
        </> string .branchName
        </> s "statuses"


fetchBranches : GitHub -> Cmd Msg
fetchBranches { apiUrl, owner, repo } =
    let
        url =
            apiUrl ++ branchesUrl @ { gitHubOwner = owner, gitHubRepo = repo }
    in
        Http.get url decodeBranchNames
            |> RemoteData.sendRequest
            |> Cmd.map BranchesFetched


fetchStatuses : GitHub -> BranchName -> Cmd Msg
fetchStatuses { apiUrl, owner, repo } branchName =
    let
        url =
            apiUrl
                ++ statusesUrl
                @ { gitHubOwner = owner
                  , gitHubRepo = repo
                  , branchName = branchName
                  }
    in
        Http.get url decodeStatuses
            |> RemoteData.sendRequest
            |> Cmd.map (StatusesFetched branchName)


updateBranchState :
    WebData Branches
    -> BranchName
    -> WebData BranchState
    -> WebData Branches
updateBranchState branches branchName webData =
    let
        updateState value =
            Maybe.map (\_ -> webData) value

        branchesDict =
            RemoteData.withDefault Dict.empty branches
                |> Dict.update branchName updateState
    in
        RemoteData.succeed branchesDict


changeColorCmd : Branches -> Cmd Msg
changeColorCmd branches =
    let
        states =
            Dict.values branches

        webDataNotSuccess state =
            not (RemoteData.isSuccess state)

        isPending state =
            (RemoteData.withDefault "error" state) == "pending"

        isFailure state =
            (RemoteData.withDefault "error" state) == "failure"

        isError state =
            (RemoteData.withDefault "error" state) == "error"

        isSuccess state =
            (RemoteData.withDefault "error" state) == "success"
    in
        if List.isEmpty states || List.any webDataNotSuccess states then
            changeColor Pink
        else if List.any isPending states then
            changeColor Yellow
        else if List.any isFailure states || List.any isError states then
            changeColor Red
        else if List.all isSuccess states then
            changeColor Green
        else
            changeColor Pink


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Connect ->
            ( { model | errorMessage = Nothing }
            , Bluetooth.connect <| Bluetooth.Bulb bulbName service
            )

        Connected bulbId ->
            ( { model | bulbId = Just bulbId }, changeColor Blue )

        Disconnect ->
            ( model, changeColor Off )

        Disconnected _ ->
            ( { model | bulbId = Nothing }, Cmd.none )

        ConnectionError error ->
            ( { model | errorMessage = Just error }, Cmd.none )

        FetchBranches _ ->
            ( model, fetchBranches model.gitHub )

        BranchesFetched RemoteData.NotAsked ->
            ( { model | branches = RemoteData.NotAsked }, Cmd.none )

        BranchesFetched RemoteData.Loading ->
            ( { model | branches = RemoteData.Loading }, Cmd.none )

        BranchesFetched (RemoteData.Success branches) ->
            let
                filterBlacklist branchName =
                    not <| List.member branchName model.gitHub.branchBlacklist

                branchesDict =
                    branches
                        |> List.filter filterBlacklist
                        |> List.map (\branch -> ( branch, RemoteData.Loading ))
                        |> Dict.fromList

                cmds =
                    Dict.keys branchesDict
                        |> List.map (fetchStatuses model.gitHub)
            in
                { model | branches = RemoteData.succeed branchesDict } ! cmds

        BranchesFetched (RemoteData.Failure err) ->
            ( { model | branches = RemoteData.Failure err }, Cmd.none )

        StatusesFetched branchName RemoteData.NotAsked ->
            ( model, Cmd.none )

        StatusesFetched branchName RemoteData.Loading ->
            let
                branches =
                    updateBranchState model.branches branchName RemoteData.Loading
            in
                ( { model | branches = branches }, Cmd.none )

        StatusesFetched branchName (RemoteData.Success statuses) ->
            let
                firstState =
                    statuses
                        |> List.sortBy .id
                        |> List.reverse
                        |> List.head

                updateState value =
                    Maybe.map2 (\_ { state } -> RemoteData.succeed state) value firstState

                branchesDict =
                    RemoteData.withDefault Dict.empty model.branches
                        |> Dict.update branchName updateState
            in
                ( { model | branches = RemoteData.succeed branchesDict }
                , changeColorCmd branchesDict
                )

        StatusesFetched branchName (RemoteData.Failure err) ->
            let
                branches =
                    updateBranchState model.branches branchName (RemoteData.Failure err)
            in
                ( { model | branches = branches }, Cmd.none )

        ChangeBulbColor color ->
            ( model, Cmd.none )

        ValueWritten { value } ->
            if value == getRgb Off then
                ( model, Bluetooth.disconnect () )
            else
                ( model, Cmd.none )


view : Model -> Html Msg
view model =
    let
        flash =
            Maybe.Extra.isJust model.bulbId

        lightBulbMsg =
            if flash then
                Disconnect
            else
                Connect
    in
        div [ class "main" ]
            [ lightBulb flash lightBulbMsg
            , errorView model
            , footerView model
            ]


errorView : Model -> Html Msg
errorView { errorMessage } =
    case errorMessage of
        Nothing ->
            div [] []

        Just message ->
            p [ class "errorMessage" ] [ text message ]


footerView : Model -> Html Msg
footerView model =
    footer []
        [ text "Icons made by "
        , a
            [ href "http://www.freepik.com"
            , title "Freepik"
            ]
            [ text "Freepik" ]
        , text " from "
        , a
            [ href "https://www.flaticon.com/"
            , title "Flaticon"
            ]
            [ text "www.flaticon.com" ]
        , text " is licensed by "
        , a
            [ href "http://creativecommons.org/licenses/by/3.0/"
            , title "Creative Commons BY 3.0"
            , target "_blank"
            ]
            [ text "CC 3.0 BY" ]
        ]


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        defaultSubs =
            [ Bluetooth.error ConnectionError
            , Bluetooth.connected Connected
            , Bluetooth.disconnected Disconnected
            , Bluetooth.valueWritten ValueWritten
            ]

        subs =
            case model.bulbId of
                Just id ->
                    Time.every (10 * second) FetchBranches :: defaultSubs

                Nothing ->
                    defaultSubs
    in
        Sub.batch subs


parseBranchBlacklist : String -> List String
parseBranchBlacklist blacklist =
    case String.trim blacklist of
        "" ->
            []

        trimmed ->
            String.split "," trimmed


init : Flags -> ( Model, Cmd Msg )
init { gitHubApiUrl, gitHubOwner, gitHubRepo, gitHubBranchBlacklist } =
    ( { gitHub =
            { apiUrl = gitHubApiUrl
            , owner = gitHubOwner
            , repo = gitHubRepo
            , branchBlacklist = parseBranchBlacklist gitHubBranchBlacklist
            }
      , bulbId = Nothing
      , branches = RemoteData.NotAsked
      , errorMessage = Nothing
      }
    , Cmd.none
    )


main : Program Flags Model Msg
main =
    Html.programWithFlags
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
