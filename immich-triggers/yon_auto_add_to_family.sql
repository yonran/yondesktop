-- Synced to the LIVE function on 2026-07-20 (Immich v3.0.3 schema).
-- NOTE: modern singular schema — "album"/"asset"/"album_asset" ("albumId"/"assetId"),
-- "album_user" ("userId"/"role"), "asset"."visibility" enum ('archive') — NOT the old
-- "albums"/"assets"/"albums_assets_assets"/"albums_shared_users_users"/"isArchived".
-- v3 CHANGE (2026-07-20): "album"."ownerId" was REMOVED in Immich v3. The album owner
-- is now the "album_user" row with "role" = 'owner' (the role enum gained 'owner').
-- Every owner lookup below reads album_user, not album.ownerId.
-- Applied manually via psql:
--   sudo podman exec -i immich-database psql -U postgres -d immich -f <thisfile>

CREATE OR REPLACE FUNCTION add_asset_to_album()
RETURNS TRIGGER AS $$
DECLARE
    album_owner_id UUID;
    lakewood_album_id UUID := '6ee340e1-7830-425f-9a29-7140aa8f737c'::UUID;
BEGIN
    -- Check if the file is from WhatsApp by filename pattern
    IF NEW."originalFileName" ~ '^IMG-[0-9]{8}-WA[0-9]+\..*$' THEN
        -- Get the album owner ID (v3: owner is the album_user row with role='owner')
        SELECT "userId" INTO album_owner_id
        FROM "album_user"
        WHERE "albumId" = lakewood_album_id
          AND "role" = 'owner';

        -- Only proceed if the asset owner matches the album owner
        IF NEW."ownerId" = album_owner_id THEN
            -- Add the asset to the Lakewood Bumblebees album
            INSERT INTO "album_asset" ("albumId", "assetId")
            VALUES (lakewood_album_id, NEW."id");

            -- Archive the asset
            UPDATE "asset"
            SET "visibility" = 'archive'
            WHERE "id" = NEW."id";
        END IF;
    ELSE
        -- Only add the asset to the album if the asset's owner is either:
        -- 1. The owner of the album
        -- 2. An editor with access to the album
        IF EXISTS (
            -- Check if asset owner is the album owner (v3: role='owner' in album_user)
            SELECT 1 FROM "album_user"
            WHERE "albumId" = 'c3e845fd-8bbd-4c9d-968f-c6535e73e477'
            AND "role" = 'owner'
            AND "userId" = NEW."ownerId"
        ) OR EXISTS (
            -- Check if asset owner is an editor of the album
            SELECT 1 FROM "album_user"
            WHERE "albumId" = 'c3e845fd-8bbd-4c9d-968f-c6535e73e477'
            AND "userId" = NEW."ownerId"
            AND "role" = 'editor'
        ) THEN
            -- Insert the new asset into the specified album
            INSERT INTO "album_asset" ("albumId", "assetId")
            VALUES ('c3e845fd-8bbd-4c9d-968f-c6535e73e477', NEW."id");
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS auto_add_to_album ON "asset";
CREATE TRIGGER auto_add_to_album
AFTER INSERT ON "asset"
FOR EACH ROW
EXECUTE FUNCTION add_asset_to_album();
