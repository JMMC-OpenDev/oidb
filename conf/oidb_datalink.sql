--
-- Table structure for table `oidb_datalink`
--
SET client_encoding = 'UTF8';

CREATE SEQUENCE oidb_datalink_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- oidb_datalink table = ObsCore + extensions
CREATE TABLE oidb_datalink (
    -- Datalink model: 
    id                bigint NOT NULL,
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
