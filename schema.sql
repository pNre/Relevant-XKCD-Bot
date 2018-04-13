DROP TABLE IF EXISTS "comic";

CREATE TABLE "comic" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "alt" TEXT DEFAULT NULL,
    "title" TEXT DEFAULT NULL,
    "img" TEXT NOT NULL,
    "w" INTEGER DEFAULT 0,
    "h" INTEGER DEFAULT 0
);
CREATE INDEX comic_alt ON comic (alt);
CREATE INDEX comic_title ON comic (title);
