ALTER TABLE public.oidb ADD dataproduct_category text NULL;
ALTER TABLE public.oidb ADD proposal_subid text NULL;
ALTER TABLE public.oidb ADD note text NULL;

INSERT INTO "TAP_SCHEMA"."columns" ("table_name", "column_name", "description", "unit", "ucd", "utype", "datatype", "size", "principal", "indexed", "std", "column_index") VALUES 
('oidb', 'dataproduct_category', 'Mainly mapped to HIERARCH DPR CATG (SCIENCE,CALIB,ACQUISITION,TECHNICAL,TEST,SIMULATION,OTHER)', '', 'meta.id', 'ObsDataset.dataProductSubtype', 'VARCHAR', '-1', '1', '0', '0', '-1');

INSERT INTO "TAP_SCHEMA"."columns" ("table_name", "column_name", "description", "unit", "ucd", "utype", "datatype", "size", "principal", "indexed", "std", "column_index") VALUES 
('oidb', 'proposal_subid', 'Proposal sub indentifier (may reference some catalogs ids)', '', 'meta.id; obs.proposal', 'Provenance.identifier', 'VARCHAR', '-1', '1', '0', '0', '-1');

INSERT INTO "TAP_SCHEMA"."columns" ("table_name", "column_name", "description", "unit", "ucd", "utype", "datatype", "size", "principal", "indexed", "std", "column_index") VALUES 
('oidb', 'note', 'Note or remark', '', 'meta.note', 'Provenance.comment', 'VARCHAR', '-1', '1', '0', '0', '-1');

