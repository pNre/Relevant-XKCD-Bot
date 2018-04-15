DROP TABLE IF EXISTS "xkcd";

CREATE TABLE "xkcd" (
    "id" INTEGER NOT NULL PRIMARY KEY,
    "alt" TEXT DEFAULT NULL,
    "title" TEXT DEFAULT NULL,
    "uri" TEXT NOT NULL,
    "w" INTEGER DEFAULT 0,
    "h" INTEGER DEFAULT 0
);
CREATE INDEX xkcd_alt ON xkcd (alt);
CREATE INDEX xkcd_title ON xkcd (title);
