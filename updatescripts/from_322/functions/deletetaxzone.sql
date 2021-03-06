CREATE OR REPLACE FUNCTION deletetaxzone(integer)
  RETURNS integer AS
$BODY$
DECLARE
pTaxzoneid ALIAS FOR $1;
_result INTEGER;

BEGIN

-- Check to find if the tax zone is used in any tax assignment
SELECT taxass_id INTO _result
FROM taxass
WHERE (taxass_taxzone_id=pTaxzoneid);
IF (FOUND) THEN
   RETURN -1;
END IF;

-- Check to find if the tax zone has been referenced in any tax registration
SELECT taxreg_id INTO _result 
FROM taxreg
WHERE (taxreg_taxzone_id=pTaxzoneid);
IF (FOUND) THEN
   RETURN -2;
END IF;

-- Delete the tax zone if none of the above conditions match
DELETE FROM taxzone WHERE taxzone_id = pTaxzoneid ;

RETURN pTaxzoneid;

END;
$BODY$
  LANGUAGE 'plpgsql' VOLATILE