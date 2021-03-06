CREATE OR REPLACE FUNCTION fetchPoNumber() RETURNS TEXT AS '
-- Copyright (c) 1999-2011 by OpenMFG LLC, d/b/a xTuple. 
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  _poNumber TEXT;
  _test INTEGER;

BEGIN

  LOOP

    SELECT CAST(orderseq_number AS text) INTO _poNumber
    FROM orderseq
    WHERE (orderseq_name=''PoNumber'');

    UPDATE orderseq
    SET orderseq_number = (orderseq_number + 1)
    WHERE (orderseq_name=''PoNumber'');

    SELECT pohead_id INTO _test
    FROM pohead
    WHERE (pohead_number=_poNumber);

    IF (NOT FOUND) THEN
      EXIT;
    END IF;

  END LOOP;

  RETURN _poNumber;

END;
' LANGUAGE 'plpgsql';
