CREATE OR ALTER PROCEDURE dbo.Nollställ
AS


TRUNCATE TABLE dbo.Transaktioner;
TRUNCATE TABLE dbo.Saldon;

INSERT INTO dbo.Transaktioner (År, Verifikationsnr, Radnr, Datum, Konto, Kst, Belopp)
SELECT YEAR(Datum)-2016 AS År,
       DENSE_RANK() OVER (PARTITION BY YEAR(Datum) ORDER BY Datum, Verifikationsnr) AS Verifikationsnr,
       ROW_NUMBER() OVER (PARTITION BY Datum, Verifikationsnr ORDER BY (SELECT NULL)) AS Radnr,
       Datum,
       Konto,
       Kst,
       Belopp
FROM (
    SELECT CAST(DATEADD(day, a._rad/200, {d '2017-01-01'}) AS date) AS Datum,
           (_rad%200)/5 AS Verifikationsnr,
           b.Konto,
           a.Kst,
           SUM(b.Belopp) AS Belopp
    FROM (
        SELECT 2*ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS _rad,
               10*CAST(100+299*RAND(CHECKSUM(msg.[text])) AS int)+1 AS Debet,
               10*CAST(100+299*RAND(CHECKSUM(msg.[text]+'.')) AS int)+1 AS Kredit,
               NULLIF(CHAR(65+(severity+message_id)%5), 'E') AS Kst,
               CAST(10000*POWER(RAND(CHECKSUM(msg.[text]+'!')), 3) AS numeric(16, 2)) AS Belopp
        FROM sys.messages AS msg
        ) AS a
    CROSS APPLY (
        VALUES (a.Kredit, -a.Belopp, 1),
               (a.Debet,   a.Belopp, 2)
        ) AS b(Konto, Belopp, Radnr)
    WHERE a.Belopp>=0.5
      AND a._rad<=250000
    GROUP BY a._rad/200, (_rad%200)/5, b.Konto, a.Kst
    ) AS x;



INSERT INTO dbo.Saldon (År, Konto, Kst, Saldo)
SELECT År, Konto, Kst, SUM(Belopp) AS Saldo
FROM dbo.Transaktioner
GROUP BY År, Konto, Kst
HAVING SUM(Belopp)!=0;

GO
CREATE OR ALTER PROCEDURE dbo.Sabba
    @Nivåer         tinyint=5,      --- Hur många transaktioner det som mest kan diffa för ett givet saldo
    @Procent_fel    tinyint=5       --- Hur många procent av saldona som innehåller fel.
AS

UPDATE s
SET s.Saldo=s.Saldo-x.Diff
FROM dbo.Saldon AS s
CROSS APPLY (
    SELECT SUM(Belopp) AS Diff, COUNT(*) AS Antal
    FROM (
        SELECT TOP (1+CAST(@Nivåer*RAND(CHECKSUM(Saldo)) AS int)) t.Belopp
        FROM dbo.Transaktioner AS t
        WHERE EXISTS (
            SELECT s.År, s.Konto, s.Kst
            INTERSECT
            SELECT t.År, t.Konto, t.Kst)
        ORDER BY NEWID()
        ) AS y
    ) AS x
WHERE ABS(CHECKSUM(s.År, s.Konto, s.Kst))%100<=@Procent_fel

GO
