{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-| Basic structures of an impure B+-tree.  -}
module Data.BTree.Impure.Structures (
  -- * Structures
  Tree(..)
, Node(..)

  -- * Binary encoding
, putNode
, getNode

  -- * Casting
, castNode
, castNode'
) where

import Control.Applicative ((<$>), (<*>))
import Data.Binary (Binary(..), Put, Get)
import Data.Map (Map)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable, typeRep)

import GHC.Generics (Generic)

import Unsafe.Coerce

import Data.BTree.Primitives

--------------------------------------------------------------------------------

{-| A B+-tree.

    This is a simple wrapper around a root 'Node'. The type-level height is
    existentially quantified, but a term-level witness is stores.
-}
data Tree key val where
    Tree :: { -- | A term-level witness for the type-level height index.
              treeHeight :: Height height
            , -- | An empty tree is represented by 'Nothing'. Otherwise it's
              --   'Just' a 'NodeId' pointer the root.
              treeRootId :: Maybe (NodeId height key val)
            } -> Tree key val

{-| A node in a B+-tree.

    Nodes are parameterized over the key and value types and are additionally
    indexed by their height. All paths from the root to the leaves have the same
    length. The height is the number of edges from the root to the leaves,
    i.e. leaves are at height zero and index nodes increase the height.

    Sub-trees are represented by a 'NodeId' that are used to resolve the actual
    storage location of the sub-tree node.
-}
data Node height key val where
    Idx  :: { idxChildren      ::  Index key (NodeId height key val)
            } -> Node ('S height) key val
    Leaf :: { leafItems        ::  Map key val
            } -> Node 'Z key val
    deriving (Typeable)

instance (Eq key, Eq val) => Eq (Node height key val) where
    Leaf x == Leaf y = x == y
    Idx x  == Idx y  = x == y

deriving instance (Show key, Show val) => Show (Node height key val)
deriving instance (Show key, Show val) => Show (Tree key val)

--------------------------------------------------------------------------------

instance Binary (Tree key val) where
    put (Tree height rootId) = put height >> put rootId
    get = Tree <$> get <*> get

data BNode = BIdx
           | BLeaf
           deriving (Generic)

instance Binary BNode where

{-| Encode a 'Node' -}
putNode :: (Binary key, Binary val) => Node height key val -> Put
putNode = \case
    Leaf items -> put BLeaf >> put items
    Idx idx    -> put BIdx  >> put idx

{-| Decode a 'Node' of a certain height. -}
getNode :: (Binary key, Binary val) => Height height -> Get (Node height key val)
getNode height = case viewHeight height of
    UZero   -> do
                   BLeaf <- get
                   Leaf <$> get
    USucc _ -> do
                   BIdx <- get
                   Idx <$> get

--------------------------------------------------------------------------------

{-| Cast a node to a different type.

    Essentially this is just a drop-in replacement for 'Data.Typeable.cast'.
-}
castNode :: forall n key1 val1 height1 key2 val2 height2.
       (Typeable key1, Typeable val1, Typeable key2, Typeable val2)
    => Height height1      -- ^ Term-level witness for the source height.
    -> Height height2      -- ^ Term-level witness for the target height.
    -> n height1 key1 val1 -- ^ Node to cast.
    -> Maybe (n height2 key2 val2)
castNode height1 height2 n
    | typeRep (Proxy :: Proxy key1) == typeRep (Proxy :: Proxy key2)
    , typeRep (Proxy :: Proxy val1) == typeRep (Proxy :: Proxy val2)
    , fromHeight height1 == fromHeight height2
    = Just (unsafeCoerce n)
    | otherwise
    = Nothing

{-| Cast a node to one of the available types. -}
castNode' :: forall n h k v.
          (Typeable k, Typeable v)
    => Height h         -- ^ Term-level witness for the source height
    -> n h k v          -- ^ Node to cast.
    -> Either (n 'Z k v) (n ('S h) k v)
castNode' h n
    | Just v <- castNode h zeroHeight n = Left v
    | otherwise                         = Right (unsafeCoerce n)

--------------------------------------------------------------------------------
