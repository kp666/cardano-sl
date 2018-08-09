module Explorer.View.Block (blockView) where

import Prelude

import Data.Array (length, null, slice)
import Data.Foldable (for_)
import Data.Lens ((^.))
import Data.Maybe (Maybe(..), isJust)

import Explorer.I18n.Lang (Language, translate)
import Explorer.I18n.Lenses (cBlock, blSlotNotFound, common, cBack2Dashboard, cOf, cLoading, cNotAvailable, block, blFees, blRoot, blNextBlock, blPrevBlock, cHash, cSummary, cTotalOutput, cHashes, cSlot, cTransactions, tx, txNotFound, txEmpty) as I18nL
import Explorer.Lenses.State (_PageNumber, blockDetail, blockTxPagination, blockTxPaginationEditable, currentBlockSummary, currentBlockTxs, lang, viewStates)
import Explorer.Routes (Route(..), toUrl)
import Explorer.State (minPagination)
import Explorer.Types.Actions (Action(..))
import Explorer.Types.State (CCurrency(..), CTxBriefs, PageNumber(..), State)
import Explorer.Util.String (formatADA)
import Explorer.View.Common (currencyCSSClass, emptyView, getMaxPaginationNumber, mkTxBodyViewProps, mkTxHeaderViewProps, txBodyView, txEmptyContentView, txHeaderView, txPaginationView)
import Explorer.View.CSS as CSS
import Explorer.View.Dashboard.Shared (headerView)
import Explorer.View.Dashboard.Types (HeaderOptions(..))

import Network.RemoteData (RemoteData(..), isFailure)

import Pos.Explorer.Web.ClientTypes (CBlockEntry(..), CBlockSummary(..), CTxBrief)
import Pos.Explorer.Web.Lenses.ClientTypes (_CBlockEntry, _CBlockSummary, _CHash, cbeBlkHash, cbeSlot, cbeTotalSent, cbeTxNum, cbsEntry, cbsMerkleRoot, cbsNextHash, cbsPrevHash, cbeFees)

import Pux.DOM.HTML (HTML) as P
import Pux.DOM.Events (onClick) as P

import Text.Smolder.HTML as S
import Text.Smolder.HTML.Attributes as SA
import Text.Smolder.Markup as SM
import Text.Smolder.Markup ((#!), (!))



blockView :: State -> P.HTML Action
blockView state =
    S.div ! SA.className CSS.pureGContainer $
      S.div ! SA.className "pure-u-1-1" $ do
        headerView state headerOptions
        case blockSummary of
            NotAsked -> blockSummaryEmptyView ""
            Loading -> blockSummaryEmptyView $ translate (I18nL.common <<< I18nL.cLoading) lang'
            Failure _ -> blockSummaryEmptyView $ translate (I18nL.block <<< I18nL.blSlotNotFound) lang'
            Success block -> blockSummaryView block lang'
        S.div ! SA.className "explorer-block__wrapper" $ do
            S.div ! SA.className "explorer-block__container" $ do
                S.h3  ! SA.className "headline"
                      $ SM.text (translate (I18nL.common <<< I18nL.cSummary) lang')
                case blockTxs of
                    NotAsked -> txEmptyContentView ""
                    Loading -> txEmptyContentView $ translate (I18nL.common <<< I18nL.cLoading) lang'
                    Failure _ -> txEmptyContentView $ translate (I18nL.tx <<< I18nL.txNotFound) lang'
                    Success txs -> blockTxsView txs state
            if (isFailure blockSummary && isFailure blockTxs)
                -- Show back button if both results ^ are failed
                then
                    S.div ! SA.className "explorer-block__container"
                          $ S.a ! SA.href (toUrl Dashboard)
                                #! P.onClick (Navigate $ toUrl Dashboard)
                                ! SA.className "btn-back"
                                $ SM.text (translate (I18nL.common <<< I18nL.cBack2Dashboard) lang')
                else
                    emptyView
    where
      lang' = state ^. lang
      blockSummary = state ^. currentBlockSummary
      blockTxs = state ^. currentBlockTxs
      headerOptions = HeaderOptions
          { headline: (translate (I18nL.common <<< I18nL.cBlock) lang')
          , link: Nothing
          , icon: Just "fa-cube"
          }

--  summary

type SummaryRowItem =
    { id :: String
    , label :: String
    , amount :: String
    , mCurrency :: Maybe CCurrency
    }

type SummaryItems = Array SummaryRowItem

mkSummaryItems :: Language -> CBlockEntry -> SummaryItems
mkSummaryItems lang (CBlockEntry entry) =
    [ { id: "0"
      , label: translate (I18nL.common <<< I18nL.cTransactions) lang
      , amount: show $ entry ^. cbeTxNum
      , mCurrency: Nothing
      }
    , { id: "1"
      , label: translate (I18nL.common <<< I18nL.cTotalOutput) lang
      , amount: formatADA (entry ^. cbeTotalSent) lang
      , mCurrency: Just ADA
      }
    -- TODO: Enable it later again ([CSE-168] Remove `Est. Volume` temporary)
    -- , { id: "2"
    --   , label: translate (I18nL.block <<< I18nL.blEstVolume) lang
    --   -- TODO: We do need real data here
    --   , amount: formatADA (mkCoin "0") lang
    --   , mCurrency: Just ADA
    --   }
    , { id: "3"
      , label: translate (I18nL.block <<< I18nL.blFees) lang
      , amount: formatADA (entry ^. cbeFees) lang
      , mCurrency: Just ADA
      }
    , { id: "4"
      , label: translate (I18nL.common <<< I18nL.cSlot) lang
      , amount: show $ entry ^. cbeSlot
      , mCurrency: Nothing
      }
    ]

summaryRow :: SummaryRowItem -> P.HTML Action
summaryRow item =
    S.tr $ do
      S.td $ SM.text item.label
      S.td $ if isJust item.mCurrency
                  then S.span ! SA.className (currencyCSSClass item.mCurrency)
                              $ SM.text item.amount
                  else SM.text item.amount

blockSummaryEmptyView :: String -> P.HTML Action
blockSummaryEmptyView message =
    S.div ! SA.className "summary-empty__container"
          $ SM.text message

blockSummaryView :: CBlockSummary -> Language -> P.HTML Action
blockSummaryView block lang = do
    S.div ! SA.className "summary-container" $ do
        S.h3  ! SA.className "subheadline"
                  $ SM.text (translate (I18nL.common <<< I18nL.cSummary) lang)
        S.table ! SA.className "pure-table pure-table-horizontal" $
          S.tbody $
            for_ (mkSummaryItems lang $ block ^. (_CBlockSummary <<< cbsEntry)) summaryRow
    S.div ! SA.className "hashes-container" $ do
        S.h3  ! SA.className "subheadline"
              $ SM.text (translate (I18nL.common <<< I18nL.cHashes) lang)
        S.table ! SA.className "pure-table pure-table-horizontal" $
          S.tbody $
            for_ (mkHashItems lang block) hashesRow

-- hashes

type HashItems = Array HashRowItem

type HashRowItem =
    { id :: String
    , label :: String
    , hash :: String
    , link :: Maybe String
    }

mkHashItems :: Language -> CBlockSummary -> HashItems
mkHashItems lang (CBlockSummary blockSummery) =
    [ { id: "0"
      , label: translate (I18nL.common <<< I18nL.cHash) lang
      , hash: blockSummery ^. (cbsEntry <<< _CBlockEntry <<< cbeBlkHash <<< _CHash)
      , link: Nothing
      }
    , { id: "1"
      , label: translate (I18nL.block <<< I18nL.blPrevBlock) lang
      , hash: blockSummery ^. (cbsPrevHash <<< _CHash)
      , link: Just <<< toUrl <<< Block $ blockSummery ^. cbsPrevHash
      }
    , { id: "2"
      , label: translate (I18nL.block <<< I18nL.blNextBlock) lang
      , hash: case blockSummery ^. cbsNextHash of
          Nothing -> translate (I18nL.common <<< I18nL.cNotAvailable) lang
          Just hash -> hash ^. _CHash
      , link: case blockSummery ^. cbsNextHash of
          Nothing -> Nothing
          Just hash -> Just <<< toUrl $ Block hash
      }
    , { id: "3"
      , label: translate (I18nL.block <<< I18nL.blRoot) lang
      , hash: blockSummery ^. (cbsMerkleRoot <<< _CHash)
      , link: Nothing
      }
    ]


hashesRow :: HashRowItem -> P.HTML Action
hashesRow item =
    S.tr $ do
      S.td $ SM.text item.label
      case item.link of
          Nothing ->
            S.td $ SM.text item.hash
          Just link ->
            S.td $
              S.a ! SA.href link
                  #! P.onClick (Navigate link)
                  ! SA.className "column column__hash--link" $
                SM.text item.hash

maxTxRows :: Int
maxTxRows = 5

blockTxsView :: CTxBriefs -> State -> P.HTML Action
blockTxsView txs state =
    if null txs then
        txEmptyContentView $ translate (I18nL.tx <<< I18nL.txEmpty) (state ^. lang)
    else
        let txPagination = state ^. (viewStates <<< blockDetail <<< blockTxPagination <<< _PageNumber)
            lang' = state ^. lang
            minTxIndex = (txPagination - minPagination) * maxTxRows
            currentTxs = slice minTxIndex (minTxIndex + maxTxRows) txs
        in
        do
            for_ currentTxs (\tx -> blockTxView tx lang')
            txPaginationView  { label: translate (I18nL.common <<< I18nL.cOf) $ lang'
                              , currentPage: PageNumber txPagination
                              , minPage: PageNumber minPagination
                              , maxPage: PageNumber $ getMaxPaginationNumber (length txs) maxTxRows
                              , changePageAction: BlockPaginateTxs
                              , editable: state ^. (viewStates <<< blockDetail <<< blockTxPaginationEditable)
                              , editableAction: BlockEditTxsPageNumber
                              , invalidPageAction: BlockInvalidTxsPageNumber
                              , disabled: false
                              }

blockTxView :: CTxBrief -> Language -> P.HTML Action
blockTxView tx lang =
    S.div ! SA.className "explorer-block__tx-container"
        $ do
        txHeaderView lang $ mkTxHeaderViewProps tx
        txBodyView lang $ mkTxBodyViewProps tx
