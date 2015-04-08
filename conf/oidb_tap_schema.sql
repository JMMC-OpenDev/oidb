--
-- TAP SCHEMA Data for oidb table
-- 
-- Note: use the oidb user to execute this script (Owner = oidb):
--   psql -U oidb oidb < oidb_tap_schema.sql
--

SET client_encoding = 'UTF8';


--
-- Delete metadata first --
--

DELETE FROM "TAP_SCHEMA"."schemas" where "schema_name" = 'public';
DELETE FROM "TAP_SCHEMA"."tables" where "table_name" = 'oidb';
DELETE FROM "TAP_SCHEMA"."columns" where "table_name" = 'oidb';


--
-- Add metadata --
--

INSERT INTO "TAP_SCHEMA"."schemas" VALUES 
('public', 'Public set of tables', NULL);

INSERT INTO "TAP_SCHEMA"."tables" VALUES 
('public', 'oidb', 'table', 'Optical interferometry database (ObsCore + extension)', NULL);


-- oidb table
INSERT INTO "TAP_SCHEMA"."columns" ("table_name", "column_name", "description", "unit", "ucd", "utype", "datatype", "size", "principal", "indexed", "std") VALUES 
    -- ObsCore model: observation information
('oidb', 'dataproduct_type', 'High level scientific classification of the data product', NULL, 'meta.id;class', 'obscore:Obs.dataProductType', 'VARCHAR', -1, 1, 0, 1),
('oidb', 'calib_level', 'Amount of data processing that has been applied to the data (0,1,2,3)', NULL, 'meta.code;obs.calib', 'obscore:Obs.calibLevel', 'INTEGER', -1, 1, 0, 1),
    -- ObsCore model: target information
('oidb', 'target_name', 'Object of interest', NULL, 'meta.id;src', 'obscore:Target.Name', 'VARCHAR', -1, 1, 0, 1),
    -- ObsCore model: data description
('oidb', 'obs_id', 'Unique identifier for an observation', NULL, 'meta.id', 'obscore:DataID.observationID', 'VARCHAR', -1, 1, 0, 1),
('oidb', 'obs_collection', 'Name of the data collection (e.g. project name) this data belongs to', NULL, 'meta.id', 'obscore:DataID.Collection', 'VARCHAR', -1, 1, 0, 1),
('oidb', 'obs_creator_name', 'Name of the creator of the data', NULL, 'meta.id', 'obscore:DataID.Creator', 'VARCHAR', -1, 1, 0, 1),
    -- ObsCore model: curation information
('oidb', 'obs_release_date', 'Observation release date', NULL, 'time.release', 'obscore:Curation.releaseDate', 'TIMESTAMP', -1, 1, 0, 1),
('oidb', 'obs_publisher_did', 'Dataset identifier given by the publisher', NULL, 'meta.ref.url;meta.curation', 'obscore:Curation.PublisherDID', 'VARCHAR', -1, 1, 0, 1),
('oidb', 'bib_reference', 'Service bibliographic reference', NULL, 'meta.bib.bibcode', 'obscore:Curation.Reference', 'VARCHAR', -1, 0, 0, 1),
('oidb', 'data_rights', 'Public/Secure/Proprietary', NULL, 'meta.code', 'obscore:Curation.Rights', 'VARCHAR', -1, 0, 0, 1),
    -- ObsCore model: access information
('oidb', 'access_url', 'URL used to obtain the data set.', NULL, 'meta.ref.url', 'obscore:Access.Reference', 'VARCHAR', -1, 1, 0, 1),
('oidb', 'access_format', 'MIME type of the resource at access_url', NULL, 'meta.code.mime', 'obscore:Access.Format', 'VARCHAR', -1, 1, 0, 1),
('oidb', 'access_estsize', 'Estimated size of data product', 'kbyte', 'phys.size;meta.file', 'obscore:Access.Size', 'BIGINT', -1, 1, 0, 1),
    -- ObsCore model: spatial characterisation
('oidb', 's_ra', 'Right ascension of (center of) observation, ICRS', 'deg', 'pos.eq.ra;meta.main', 'obscore:Char.SpatialAxis.Coverage.Location.Coord.Position2D.Value2.C1', 'DOUBLE', -1, 1, 0, 1),
('oidb', 's_dec', 'Declination of (center of) observation, ICRS', 'deg', 'pos.eq.dec;meta.main', 'obscore:Char.SpatialAxis.Coverage.Location.Coord.Position2D.Value2.C2', 'DOUBLE', -1, 1, 0, 1),
('oidb', 's_fov', 'Approximate spatial extent for the region covered by the observation', 'deg', 'phys.angSize;instr.fov', 'obscore:Char.SpatialAxis.Coverage.Bounds.Extent.diameter', 'REAL', -1, 1, 0, 1),
('oidb', 's_region', 'Region covered by the observation, as a polygon', NULL, 'phys.angArea;obs', 'obscore:Char.SpatialAxis.Coverage.Support.Area', 'REAL', -1, 1, 0, 1),
('oidb', 's_resolution', 'Best spatial resolution within the data set', 'arcsec', 'pos.angResolution', 'obscore:Char.SpatialAxis.Resolution.refval', 'REAL', -1, 1, 0, 1),
    -- ObsCore model: time characterisation
('oidb', 't_min', 'Lower bound of times represented in the data set, as MJD', 'd', 'time.start;obs.exposure', 'obscore:Char.TimeAxis.Coverage.Bounds.Limits.Interval.StartTime', 'REAL', -1, 1, 0, 1),
('oidb', 't_max', 'Upper bound of times represented in the data set, as MJD', 'd', 'time.end;obs.exposure', 'obscore:Char.TimeAxis.Coverage.Bounds.Limits.Interval.StopTime', 'REAL', -1, 1, 0, 1),
('oidb', 't_exptime', 'Total exposure time', 's', 'time.duration;obs.exposure', 'obscore:Char.TimeAxis.Coverage.Support.Extent', 'REAL', -1, 1, 0, 1),
('oidb', 't_resolution', 'Minimal significant time interval along the time axis', 's', 'time.resolution', 'obscore:Char.TimeAxis.Resolution.refval', 'REAL', -1, 1, 0, 1),
    -- ObsCore model: spectral characterisation
('oidb', 'em_min', 'Minimal wavelength represented within the data set', 'm', 'em.wl;stat.min', 'obscore:Char.SpectralAxis.Coverage.Bounds.Limits.Interval.LoLim', 'REAL', -1, 1, 0, 1),
('oidb', 'em_max', 'Maximal wavelength represented within the data set', 'm', 'em.wl;stat.max', 'obscore:Char.SpectralAxis.Coverage.Bounds.Limits.Interval.HiLim', 'REAL', -1, 1, 0, 1),
('oidb', 'em_res_power', 'Spectral resolving power delta_lambda / lamda', NULL, 'spect.resolution', 'obscore:Char.SpectralAxis.Resolution.ResolPower.refval', 'REAL', -1, 1, 0, 1),
    -- ObsCore model: observable axis
('oidb', 'o_ucd', 'UCD for the product''s observable', NULL, 'meta.ucd', 'obscore:Char.ObservableAxis.ucd', 'VARCHAR', -1, 1, 0, 1),
    -- ObsCore model: polarisation axis
('oidb', 'pol_states', 'List of polarization states in the data set', NULL, 'meta.code;phys.polarization', 'obscore:Char.PolarizationAxis.stateList', 'VARCHAR', -1, 1, 0, 1),
    -- ObsCore model: provenance
('oidb', 'facility_name', 'Name of the facility at which data was taken', NULL, 'meta.id;instr.tel', 'obscore:Provenance.ObsConfig.facility.name', 'VARCHAR', -1, 1, 0, 1),
('oidb', 'instrument_name', 'Name of the instrument that produced the data', NULL, 'meta.id;instr', 'obscore:Provenance.ObsConfig.instrument.name', 'VARCHAR', -1, 1, 0, 1),
    -- OiDB Extension (OIFits metadata)
-- TODO: add description, ucd ?    
('oidb', 'instrument_mode', 'Instrument mode', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 0),
('oidb', 'quality_level', 'Quality data level estimated by data provider', NULL, 'meta.code.qual', NULL, 'INTEGER', -1, 0, 0, 0),
('oidb', 'nb_channels', 'number of spectral channels', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 0),
('oidb', 'nb_vis', 'number of OI_VIS data (complex visiblity)', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 0),
('oidb', 'nb_vis2', 'number of OI_VIS2 data (square visiblity)', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 0),
('oidb', 'nb_t3', 'number of OI_T3 data (closure phase)', NULL, NULL, NULL, 'INTEGER', -1, 0, 0, 0),
('oidb', 'keywords', NULL, NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 0),
('oidb', 'subdate', 'submission date', NULL, NULL, NULL, 'TIMESTAMP', -1, 0, 0, 0),
('oidb', 'id', 'Object ID', 'internal ID (granule ID)', NULL, NULL, 'BIGINT', -1, 0, 0, 0),
('oidb', 'progid', 'program or proposal identifier', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 0),
('oidb', 'datapi', 'Data PI', NULL, NULL, NULL, 'VARCHAR', -1, 0, 0, 0)
;

--
-- END
--
