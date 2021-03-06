--  eidolon -- A simple gallery in Haskell and Yesod
--  Copyright (C) 2015  Amedeo Molnár
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU Affero General Public License as published
--  by the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU Affero General Public License for more details.
--
--  You should have received a copy of the GNU Affero General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.

module Handler.AdminProfileSettings where

import Import
import Handler.Commons
import qualified Data.Text as T
import qualified Data.List as L
import Data.Maybe
import System.Directory
import System.FilePath

getAdminProfilesR :: Handler Html
getAdminProfilesR = do
  adminCheck <- loginIsAdmin
  case adminCheck of
    Right _ -> do
      profiles <- runDB $ selectList [] [Desc UserName]
      defaultLayout $ do
        setTitle "Administration: Profiles"
        $(widgetFile "adminProfiles")
    Left (errorMsg, route) -> do
      setMessage errorMsg
      redirect $ route

getAdminUserAlbumsR :: UserId -> Handler Html
getAdminUserAlbumsR ownerId = do
  adminCheck <- loginIsAdmin
  case adminCheck of
    Right _ -> do
      tempOwner <- runDB $ get ownerId
      case tempOwner of
        Just owner -> do
          albums <- runDB $ selectList [AlbumOwner ==. ownerId] [Desc AlbumTitle]
          defaultLayout $ do
            setTitle "Administration: User albums"
            $(widgetFile "adminUserAlbums")
        Nothing -> do
          setMessage "This user does not exist"
          redirect $ AdminR
    Left (errorMsg, route) -> do
      setMessage errorMsg
      redirect $ route

getAdminUserMediaR :: UserId -> Handler Html
getAdminUserMediaR ownerId = do
  adminCheck <- loginIsAdmin
  case adminCheck of
    Right _ -> do
      tempOwner <- runDB $ get ownerId
      case tempOwner of
        Just owner -> do
          media <- runDB $ selectList [MediumOwner ==. ownerId] [Desc MediumTitle]
          defaultLayout $ do
            setTitle "Administration: User media"
            $(widgetFile "adminUserMedia")
        Nothing -> do
          setMessage "This user does not exist"
          redirect $ AdminR
    Left (errorMsg, route) -> do
      setMessage errorMsg
      redirect $ route

getAdminProfileSettingsR :: UserId -> Handler Html
getAdminProfileSettingsR ownerId = do
  adminCheck <- loginIsAdmin
  case adminCheck of
    Right _ -> do
      tempOwner <- runDB $ get ownerId
      case tempOwner of
        Just owner -> do
          tempUserId <- lookupSession "userId"
          userId <- return $ getUserIdFromText $ fromJust tempUserId
          (adminProfileSetWidget, enctype) <- generateFormPost $ adminProfileForm owner
          formLayout $ do
            setTitle "Administration: Profile settings"
            $(widgetFile "adminProfileSettings")
        Nothing -> do
          setMessage "This user does not exist"
          redirect $ AdminR
    Left (errorMsg, route) -> do
      setMessage errorMsg
      redirect $ route

postAdminProfileSettingsR :: UserId -> Handler Html
postAdminProfileSettingsR ownerId = do
  adminCheck <- loginIsAdmin
  case adminCheck of
    Right _ -> do
      tempOwner <- runDB $ get ownerId
      case tempOwner of
        Just owner -> do
          ((result, _), _) <- runFormPost $ adminProfileForm owner
          case result of
            FormSuccess temp -> do
              runDB $ update ownerId 
                [ UserName =. (userName temp)
                , UserSlug =. (userSlug temp)
                , UserEmail =. (userEmail temp)
                , UserAdmin =. (userAdmin temp)
                ]
              setMessage "User data updated successfully"
              redirect $ AdminR
            _ -> do
              setMessage "There was an error"
              redirect $ AdminProfileSettingsR ownerId
        Nothing -> do
          setMessage "This user does not exist"
          redirect $ AdminR
    Left (errorMsg, route) -> do
      setMessage errorMsg
      redirect $ route


adminProfileForm :: User -> Form User
adminProfileForm owner = renderDivs $ User
  <$> areq textField "Username" (Just $ userName owner)
  <*> areq textField "Userslug" (Just $ userSlug owner)
  <*> areq emailField "Email" (Just $ userEmail owner)
  <*> pure (userSalt owner)
  <*> pure (userSalted owner)
  <*> pure (userAlbums owner)
  <*> areq boolField "Admin" (Just $ userAdmin owner)

getAdminProfileDeleteR :: UserId -> Handler Html
getAdminProfileDeleteR ownerId = do
  adminCheck <- loginIsAdmin
  case adminCheck of
    Right _ -> do
      tempOwner <- runDB $ get ownerId
      case tempOwner of
        Just owner -> do
          albumList <- return $ userAlbums owner
          _ <- mapM (\albumId -> do
            album <- runDB $ getJust albumId
            mediaList <- return $ albumContent album
            _ <- mapM (\med -> do
              -- delete comments
              commEnts <- runDB $ selectList [CommentOrigin ==. med] []
              _ <- mapM (\ent -> runDB $ delete $ entityKey ent) commEnts
              -- delete media files
              medium <- runDB $ getJust med
              liftIO $ removeFile (normalise $ L.tail $ mediumPath medium)
              liftIO $ removeFile (normalise $ L.tail $ mediumThumb medium)
              -- delete medium database entry
              runDB $ delete med
              ) mediaList
            runDB $ delete albumId
            ) albumList
          runDB $ delete ownerId
          liftIO $ removeDirectoryRecursive $ "static" </> "data" </> (T.unpack $ extractKey ownerId)
          setMessage "User successfully deleted"
          redirect $ AdminR
        Nothing -> do
          setMessage "This user does not exist"
          redirect $ AdminR
    Left (errorMsg, route) -> do
      setMessage errorMsg
      redirect $ route
