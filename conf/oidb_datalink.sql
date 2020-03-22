--
-- Table structure for table `oidb_datalink`
--
SET client_encoding = 'UTF8';

-- oidb_datalink table = ObsCore + extensions
CREATE TABLE oidb_datalink (
    -- Datalink model: 
    id                bigint REFERENCES oidb(id),
    -- 
    access_url        text,
    service_def       text,
    error_message     text,
    description       text,
    semantics         text, -- should not be null
    content_type      text,
    content_length    bigint

);

--
-- END
--
