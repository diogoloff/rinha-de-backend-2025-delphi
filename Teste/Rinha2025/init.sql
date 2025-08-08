/******************************************************************************/
/****                                Tables                                ****/
/******************************************************************************/



CREATE TABLE PAYMENTS (
    ID              CHAR(36) NOT NULL,
    SERVICE         INTEGER NOT NULL,
    CORRELATION_ID  CHAR(36) NOT NULL,
    AMOUNT          NUMERIC(10,2) NOT NULL,
    CREATED_AT      TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
);



/******************************************************************************/
/****                             Primary keys                             ****/
/******************************************************************************/

ALTER TABLE PAYMENTS ADD PRIMARY KEY (ID);


/******************************************************************************/
/****                               Triggers                               ****/
/******************************************************************************/



SET TERM ^ ;



/******************************************************************************/
/****                         Triggers for tables                          ****/
/******************************************************************************/



/* Trigger: PAYMENTS_BI */
CREATE TRIGGER PAYMENTS_BI FOR PAYMENTS
ACTIVE BEFORE INSERT POSITION 0
AS
BEGIN
  IF (NEW.id IS NULL) THEN
    NEW.id = UUID_TO_CHAR(GEN_UUID());
END
^
SET TERM ; ^