CREATE OR REPLACE FUNCTION fetchInvcNumber() RETURNS INTEGER AS '
-- Copyright (c) 1999-2012 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _invcNumber INTEGER;
  _test INTEGER;

BEGIN

  LOOP

    SELECT orderseq_number INTO _invcNumber
    FROM orderseq
    WHERE (orderseq_name=''InvcNumber'');

    UPDATE orderseq
    SET orderseq_number = (orderseq_number + 1)
    WHERE (orderseq_name=''InvcNumber'');

    SELECT cobmisc_id INTO _test
    FROM cobmisc
    WHERE (cobmisc_invcnumber=_invcNumber);

    IF (NOT FOUND) THEN
      EXIT;
    END IF;

  END LOOP;

  RETURN _invcNumber;

END;
' LANGUAGE 'plpgsql';
