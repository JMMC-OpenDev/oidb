--
-- TAP SCHEMA Data for oidb_datalink table
-- 
-- Note: use the oidb user to execute this script (Owner = oidb):
--   psql -U oidb oidb < oidb_datalink_tap_schema.sql
-- this script does not create the TAP_SCHEMA table , please use oidb_schema.sql before

SET client_encoding = 'UTF8';

DELETE FROM "TAP_SCHEMA"."tables" where "table_name" = 'oidb_datalink';
DELETE FROM "TAP_SCHEMA"."columns" where "table_name" = 'oidb_datalink';


INSERT INTO "TAP_SCHEMA"."tables" VALUES 
('public', 'oidb_datalink', 'table', 'Optical interferometry database (Datalink part)', NULL);

-- oidb_datalink table
INSERT INTO "TAP_SCHEMA"."columns" ("table_name", "column_name", "description", "unit", "ucd", "utype", "datatype", "size", "principal", "indexed", "std") VALUES 
    -- ObsCore model: data description
('oidb_datalink', 'id',             'internal ID (granule ID)',                              NULL,    'meta.id;meta.main',   NULL,                       'BIGINT',  -1, 0, 0, 0),
('oidb_datalink', 'access_url',     'link to data or service',                               NULL,    'meta.ref.url',        'obscore:Access.Reference', 'VARCHAR', -1, 1, 0, 1),
('oidb_datalink', 'service_def',    'reference to a service descriptor resource',            NULL,    'meta.ref',            NULL,                       'VARCHAR', -1, 0, 0, 0),
('oidb_datalink', 'error_message',  'error if an access_url cannot be created',              NULL,    'meta.code.error',     NULL,                       'VARCHAR', -1, 0, 0, 0),
('oidb_datalink', 'description',    'human-readable text describing this link',              NULL,    'meta.note',           NULL,                       'VARCHAR', -1, 0, 0, 0),
('oidb_datalink', 'semantics',      'term from a controlled vocabulary describing the link', NULL,    'meta.code',           NULL,                       'VARCHAR', -1, 0, 0, 0),
('oidb_datalink', 'content_type',   'mime-type of the content the link returns',             NULL,    'meta.code.mime',      'obscore:Access.Format',    'VARCHAR', -1, 1, 0, 1),
('oidb_datalink', 'content_length', 'size of the download the link returns',                 'kbyte', 'phys.size;meta.file', 'obscore:Access.Size',      'BIGINT',  -1, 1, 0, 1)
;

--
-- END
--
