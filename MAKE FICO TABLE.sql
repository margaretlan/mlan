USE [SB_PA_Margaret]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP TABLE #FICO_ALL;

DECLARE @DATE_KEY INT = 20180228;  -- SET MONTH END DATE
DECLARE @LAST_MON INT = 20180131;  -- SET LAST MONTH END DATE

WITH AFS_ORIG AS (
SELECT CONCAT('0',[OBG_NO] ,'-',right(CONCAT('0000', [OBL_NO]),4)) AS acct_nbr, SHORT_NAME, CAST(CR_SCR AS INT) AS CR_SCR, [CR_DT]
FROM [EagleVision].dbo.[V_AFSR_OBLN_CURR] 
WHERE ((CR_SCR)>299 And (CR_SCR)<851 AND CR_SCR IS NOT NULL) 
)

SELECT EOM.DATE_KEY
	  ,EOM.SRC_TYPE_CD
	  ,EOM.Acct_Nbr
	  ,EOM.[ACCT_OPEN_DT] AS ORIG_DT
	  --,EOM.[BALANCE_SHEET_CATEGORY_CA]
	  ,CASE 
			WHEN EOM.SRC_TYPE_CD = 'AFS' THEN
				   CASE WHEN EOM.[BALANCE_SHEET_CATEGORY_CA] in ('Commercial Real Estate Mtgs','Multifamily Mtgs 5+ Units')
						THEN IIF(IP.[BorGtr_FICO] IS NULL, IIF(LEN(EMP.FICO)<1, PL.A15738_MinFICO, TRY_CAST(RIGHT(EMP.FICO,3) AS INT)), IP.[BorGtr_FICO])
				   ELSE IIF(AFS_ORIG.CR_SCR IS NULL, IIF(LEN(EMP.FICO)<1, PL.A15738_MinFICO, TRY_CAST(RIGHT(EMP.FICO,3) AS INT)),AFS_ORIG.CR_SCR)  END
			WHEN EOM.SRC_TYPE_CD = 'IL' 
				THEN IIF(LEN(ILORIG.[CRED_BUR_SCORE_CD] ) <1, 
						IIF(LEN(EMP.FICO)<1, PL.A15738_MinFICO, TRY_CAST(RIGHT(EMP.FICO,3) AS INT)), 
						TRY_CAST(RTRIM(LTRIM(ILORIG.[CRED_BUR_SCORE_CD]))  AS INT))
			WHEN EOM.SRC_TYPE_CD = 'ML' 
				THEN IIF(LEN(MLORIG.[CHAR_VALUE_AMT]) <1, 
						IIF(LEN(EMP.FICO)<1, PL.A15738_MinFICO, TRY_CAST(RIGHT(EMP.FICO,3) AS INT)), 
						TRY_CAST(RTRIM(LTRIM(MLORIG.[CHAR_VALUE_AMT]))  AS INT))
			ELSE IIF(LEN(EMP.FICO)<1, PL.A15738_MinFICO, TRY_CAST(RIGHT(EMP.FICO,3) AS INT))
	   END AS FICO_ORIG
	  ,CASE
			WHEN EOM.SRC_TYPE_CD = 'AFS' THEN
				CASE WHEN EOM.[ACCT_OPEN_DT] >= DATEADD(month, DATEDIFF(month, 0, CONVERT(DATE, CONVERT(VARCHAR(20), @DATE_KEY))), 0)
					THEN 
						CASE WHEN EOM.[BALANCE_SHEET_CATEGORY_CA] in ('Commercial Real Estate Mtgs','Multifamily Mtgs 5+ Units')
							THEN IIF(IP.[BorGtr_FICO] IS NULL, PL.A15738_MinFICO, IP.[BorGtr_FICO])
						ELSE  PL.A15738_MinFICO END
				ELSE RDM.FICO_CURR END
			WHEN EOM.SRC_TYPE_CD = 'IL' THEN
				CASE WHEN EOM.[ACCT_OPEN_DT] >= DATEADD(month, DATEDIFF(month, 0, CONVERT(DATE, CONVERT(VARCHAR(20), @DATE_KEY))), 0)
						THEN IIF(LEN(ILCURR.[CHAR_VALUE_AMT]) <1, 
								IIF(LEN(ILCOBOR.[CHAR_VALUE_AMT]) <1, TRY_CAST(RTRIM(LTRIM(ILORIG.[CRED_BUR_SCORE_CD])) AS INT), 
										TRY_CAST(RTRIM(LTRIM(ILCOBOR.[CHAR_VALUE_AMT])) AS INT)),
							TRY_CAST(RTRIM(LTRIM(ILCURR.[CHAR_VALUE_AMT])) AS INT))
					 ELSE IIF(LEN(ILCURR.[CHAR_VALUE_AMT]) <1, TRY_CAST(RTRIM(LTRIM(ILCOBOR.[CHAR_VALUE_AMT])) AS INT), TRY_CAST(RTRIM(LTRIM(ILCURR.[CHAR_VALUE_AMT])) AS INT)) 
				END
			WHEN EOM.SRC_TYPE_CD = 'ML' THEN
				CASE WHEN EOM.[ACCT_OPEN_DT] >= DATEADD(month, DATEDIFF(month, 0, CONVERT(DATE, CONVERT(VARCHAR(20), @DATE_KEY))), 0)
						THEN IIF(MLCURR.[RISK_SCORE] IS NULL, IIF(LEN(MLCOBOR.[CHAR_VALUE_AMT]) < 1
								,IIF(LEN(MLORIG.[CHAR_VALUE_AMT]) <1, PL.A15738_MinFICO, TRY_CAST(RTRIM(LTRIM(MLORIG.[CHAR_VALUE_AMT])) AS INT))
									, TRY_CAST(RTRIM(LTRIM(MLCOBOR.[CHAR_VALUE_AMT])) AS INT) )
									,CAST(MLCURR.[RISK_SCORE] AS INT)  )
					 ELSE CAST(MLCURR.[RISK_SCORE] AS INT) END
			ELSE RDM.FICO_CURR
	   END AS FICO_CURR
	   ,CASE 
			WHEN EOM.SRC_TYPE_CD = 'IL' THEN ILORIG.[OIL_LOAN_SCORE_DT]
			WHEN EOM.SRC_TYPE_CD = 'ML' THEN MLDT.[DATE_VALUE_AMT]
			ELSE GETDATE()
	   END AS FICO_CURR_DT

  INTO #FICO_ALL

  FROM [CreditAdmin].[dbo].[CA_GL_RECONCILED_MAKE_TABLE_CURR] EOM
  
  LEFT JOIN [RDM_Loan].[ADJ].[V_LOAN_GL_RECONCILED_EOM] RDM
	ON RDM.ACCT_NBR = EOM.ACCT_NBR AND RDM.[DATE_KEY] = @LAST_MON --APPEND LAST MONTH FICO CURRENT VALUE
  
  LEFT JOIN [CREMF].[dbo].[CRE_Collateral] IP
    ON right(EOM.Bisys_Nbr_Fmt,8)=IP.[BisysNo_Short] 
		AND (IP.[BorGtr_FICO]<851 AND IP.[BorGtr_FICO] >299 AND IP.[BorGtr_FICO] IS NOT NULL)

----==============================ORIGINAL FICO SOURCE================================================================
  LEFT JOIN AFS_ORIG ON AFS_ORIG.ACCT_NBR = EOM.ACCT_NBR

  LEFT JOIN [EagleVision].[dbo].[V_TVN_ML_USER_DEF_MSTR_REC_CURR] MLORIG 
	ON EOM.ACCT_NBR = CAST(MLORIG.ACCT_NBR AS VARCHAR) AND MLORIG.MSTR_REC_NBR=473
		AND TRY_CAST(RTRIM(LTRIM(MLORIG.[CHAR_VALUE_AMT])) AS INT) < 851
		AND TRY_CAST(RTRIM(LTRIM(MLORIG.[CHAR_VALUE_AMT])) AS INT) > 299
  
  LEFT JOIN [EagleVision].[dbo].[V_TVN_INST_LOAN_ACCT_CURR] ILORIG 
	ON CAST(ILORIG.ACCT_NBR AS VARCHAR) = EOM.ACCT_NBR
		AND TRY_CAST(RTRIM(LTRIM(ILORIG.[CRED_BUR_SCORE_CD]))  AS INT) < 851
		AND TRY_CAST(RTRIM(LTRIM(ILORIG.[CRED_BUR_SCORE_CD]))  AS INT) > 299

  LEFT JOIN [PLProd].[dbo].[vw_powerlender] PL
	ON (PL.A15738_MinFICO<851 AND PL.A15738_MinFICO>299 AND PL.A15738_MinFICO IS NOT NULL)
	AND PL.A304_CustomerKey =
		CASE WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
			 ELSE RIGHT(EOM.Bisys_Nbr_Fmt,8)
		END

  LEFT JOIN [PLProd_EMPLOYEE].[dbo].[VW_LOAN_FACT_EMP_CUSO] EMP
	ON (EMP.FICO<851 AND EMP.FICO>299 AND EMP.FICO IS NOT NULL)
	AND EMP.[Customer_key] =
		CASE WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
			 ELSE RIGHT(EOM.Bisys_Nbr_Fmt,8)
		END
----==============================CURRENT FICO SOURCE================================================================

  LEFT JOIN [EagleVision].[dbo].[V_TVN_ML_DELINQ_RECS_CURR] MLCURR 
	ON EOM.ACCT_NBR = CAST(MLCURR.ACCT_NBR AS VARCHAR) 
	AND CAST(MLCURR.[RISK_SCORE] AS INT) < 851 AND CAST(MLCURR.[RISK_SCORE] AS INT) > 299 AND CAST(MLCURR.[RISK_SCORE] AS INT) IS NOT NULL

  LEFT JOIN [EagleVision].[dbo].[V_TVN_ML_USER_DEF_MSTR_REC_CURR] MLCOBOR
	ON EOM.ACCT_NBR = CAST(MLCOBOR.ACCT_NBR AS VARCHAR) AND MLCOBOR.MSTR_REC_NBR=476
		AND TRY_CAST(RTRIM(LTRIM(MLCOBOR.[CHAR_VALUE_AMT])) AS INT) < 851
		AND TRY_CAST(RTRIM(LTRIM(MLCOBOR.[CHAR_VALUE_AMT])) AS INT) > 299 

  LEFT JOIN [EagleVision].[dbo].[V_TVN_IL_USER_DEF_MSTR_REC_CURR] ILCURR 
	ON CAST(ILCURR.ACCT_NBR AS VARCHAR) = EOM.ACCT_NBR AND ILCURR.[MSTR_REC_NBR] = 720
	AND TRY_CAST(RTRIM(LTRIM(ILCURR.[CHAR_VALUE_AMT])) AS INT) < 851
	AND TRY_CAST(RTRIM(LTRIM(ILCURR.[CHAR_VALUE_AMT])) AS INT) > 299
  
  LEFT JOIN [EagleVision].[dbo].[V_TVN_IL_USER_DEF_MSTR_REC_CURR] ILCOBOR 
	ON CAST(ILCOBOR.ACCT_NBR AS VARCHAR) = EOM.ACCT_NBR AND ILCOBOR.[MSTR_REC_NBR] = 722
	AND TRY_CAST(RTRIM(LTRIM(ILCOBOR.[CHAR_VALUE_AMT])) AS INT) < 851
	AND TRY_CAST(RTRIM(LTRIM(ILCOBOR.[CHAR_VALUE_AMT])) AS INT) > 299

 -- LEFT JOIN [PLProd].[dbo].[vw_LoanFacts] PLF
	--ON PLF.Loan_Key =
	--	CASE 
	--	WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
	--		 THEN LEFT(EOM.Bisys_Nbr_Fmt,2) + '-0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
	--	ELSE 
	--		 EOM.Bisys_Nbr_Fmt
	--	END
----==============================CURRENT FICO DATE================================================================
  LEFT JOIN [EagleVision].[dbo].[V_TVN_ML_USER_DEF_MSTR_REC_CURR] MLDT
	ON EOM.ACCT_NBR = CAST(MLDT.ACCT_NBR AS VARCHAR) AND MLDT.MSTR_REC_NBR=482
  
 -- LEFT JOIN [EagleVision].[dbo].[V_TVN_INST_LOAN_ACCT_CURR] ILDT
	--ON CAST(ILORIG.ACCT_NBR AS VARCHAR) = EOM.ACCT_NBR
  
  WHERE EOM.Date_Key=@DATE_KEY AND EOM.SRC_TYPE_CD in ('AFS','ML','IL') 
  --AND Status_Description='OPEN'
  --AND ((PL.A15738_MinFICO<950 AND PL.A15738_MinFICO>300) OR (IP.[BorGtr_FICO]<950 AND IP.[BorGtr_FICO] >300))
  --ORDER BY SRC_TYPE_CD, Balance_Sheet_Category, ORIG_LTV DESC
   

/**---==CHECK #1=CHECK ON NULL CURRENT FICO, RERUN AFTER UPDATE TO COMPARE CHANGES====CHECK #2================= 
 SELECT * FROM #FICO_ALL
 WHERE --FICO_CURR IS NULL 
 FICO_ORIG IS NULL 
 FICO_CURR > 850 
 **/
/**-------===UPDATE #1======UPDATE CURRENT AND ORIGINAL FICO=====================
    UPDATE A
	SET A.FICO_ORIG = RDM.FICO_ORIG
	FROM #FICO_ALL A
	LEFT JOIN [RDM_Loan].[ADJ].[V_LOAN_GL_RECONCILED_EOM] RDM ON RDM.ACCT_NBR = A.ACCT_NBR AND RDM.[DATE_KEY] = 20180131
	WHERE A.FICO_ORIG IS NULL AND (RDM.FICO_ORIG <851 AND RDM.FICO_ORIG >299);

------CHECK UNIQUE LENGTH OF ACCOUNT NUMBER IN QTR REFRESHED FICO FILE AND RUN UPDATE
------SELECT DISTINCT LEN([ACCOUNT #]) FROM  [CreditAdmin].[FRB\mlan].CURRENT_FICO_20171231 
	WITH TEMP AS (
		SELECT DISTINCT [ACCOUNT #] ,AVG( MedianDESC) AVG1--, AVG(MedianDESC_TRANCHE1) AVG2
		FROM [CreditAdmin].[FRB\mlan].CURRENT_FICO_20171231 
		GROUP BY [ACCOUNT #]
	)
	UPDATE A
	SET A.[FICO_CURR] = TEMP.AVG1, A.FICO_CURR_DT = '2/13/2018'
	FROM #FICO_ALL A
	LEFT JOIN TEMP ON A.[ACCT_NBR] = CASE WHEN LEN(TEMP.[ACCOUNT #]) = 15 THEN TEMP.[ACCOUNT #]
								ELSE REPLACE(TEMP.[ACCOUNT #], '-','') END
	WHERE (TEMP.AVG1 < 851 AND TEMP.AVG1 > 299)
		AND ( (A.FICO_CURR_DT > '2/13/2018' AND A.[FICO_CURR] IS NULL) 
		OR (A.FICO_CURR_DT IS NULL OR A.FICO_CURR_DT <'2/13/2018'))
	--TEMP.AVG1 < 851 AND TEMP.AVG1 > 299;
	-- AND TEMP.AVG1 IS NOT NULL)
**/
/**---====UPDATE #2======= UPDATE INVALID FICO TO NULL==============
	UPDATE #FICO_ALL
	SET #FICO_ALL.FICO_ORIG = NULL
	FROM #FICO_ALL 
	WHERE #FICO_ALL.FICO_ORIG <300 OR #FICO_ALL.FICO_ORIG >850 OR #FICO_ALL.FICO_ORIG= 0;

	UPDATE #FICO_ALL
	SET #FICO_ALL.FICO_CURR = NULL
	FROM #FICO_ALL 
	WHERE #FICO_ALL.FICO_CURR <300 OR #FICO_ALL.FICO_CURR >850 OR #FICO_ALL.FICO_CURR = 0;
**/
----===========================================================================================================================================
	  
/*FICO DATA MAPPING AS OF 20180131 ===================================================================================================
                CURRENT FICO	      
SYSTEM	DATA FIELD	          TABLE
AFS	    Access procedure	   
IL	    [CHAR_VALUE_AMT]	 [EagleVision].[dbo].[V_TVN_IL_USER_DEF_MSTR_REC_CURR]	   
ML	    [RISK_SCORE]	     [EagleVision].[dbo].[V_TVN_ML_DELINQ_RECS_CURR]
IP	    Access procedure	
		         ORIGINAL FICO	 
SYSTEM   DATA FIELD	          TABLE	   
AFS	     Access procedure	   
IL	    [CRED_BUR_SCORE_CD]	 [EagleVision].[dbo].[V_TVN_INST_LOAN_ACCT_CURR]	   
ML	    [CHAR_VALUE_AMT]	 [EagleVision].[dbo].[V_TVN_ML_USER_DEF_MSTR_REC_CURR]	   
IP	    [BorGtr_FICO]	     [CREMF].[dbo].[CRE_Collateral]	
**/

/**----===========================================================================================================================================
DELETE FROM  [SB_PA_Margaret].[FRB\mlan].[TBL_FICO_TEMP]  WHERE DATE_KEY = 20180228

INSERT INTO [SB_PA_Margaret].[FRB\mlan].[TBL_FICO_TEMP]
(

       [DATE_KEY]
      ,[SRC_TYPE_CD]
      ,[Acct_Nbr]
      ,[ORIG_DT]
      ,[FICO_ORIG]
      ,[FICO_CURR]
      ,[FICO_CURR_DT]
      ,[INSERT_DT]  )
  
SELECT [DATE_KEY], [SRC_TYPE_CD],  [Acct_Nbr], [ORIG_DT], [FICO_ORIG], [FICO_CURR], [FICO_CURR_DT], GETDATE()
FROM #FICO_ALL
--WHERE [FICO_ORIG] < 300 OR [FICO_ORIG] > 850 OR [FICO_CURR] < 300 OR [FICO_CURR] > 850

**/
-------=====================CREATE FICO WB FILE==================================================
--SELECT 'FICO_ORIG' AS FIELD, ACCT_NBR, SRC_TYPE_CD, FICO_ORIG AS VALUE, 
--	CONVERT(DATE, '02/28/2018') AS EFFECTIVE_FROM_DT, '' AS EFFECTIVE_TO_DT, 'Original FICO Score Update' AS REASON, 'mlan' AS [USER_ID]
--FROM [SB_PA_Margaret].[FRB\mlan].[TBL_FICO_TEMP]
----WHERE FICO_ORIG IS NOT NULL
--UNION
--SELECT 'FICO_CURR' AS FIELD, ACCT_NBR, SRC_TYPE_CD, FICO_CURR AS VALUE, 
--	CONVERT(DATE, '02/28/2018') AS EFFECTIVE_FROM_DT, '' AS EFFECTIVE_TO_DT, 'Current FICO Score Update' AS REASON, 'mlan' AS [USER_ID]
--FROM [SB_PA_Margaret].[FRB\mlan].[TBL_FICO_TEMP]
--UNION
--SELECT 'FICO_CURR_DT' AS FIELD, ACCT_NBR, SRC_TYPE_CD, FICO_CURR_DT AS VALUE, 
--	CONVERT(DATE, '02/28/2018') AS EFFECTIVE_FROM_DT, '' AS EFFECTIVE_TO_DT, 'Current FICO Date Update' AS REASON, 'mlan' AS [USER_ID]
--FROM [SB_PA_Margaret].[FRB\mlan].[TBL_FICO_TEMP]
--WHERE FICO_CURR_DT IS NOT NULL