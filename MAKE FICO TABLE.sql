USE [PA_Reporting]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

DECLARE @DATE_KEY INT = 20180131;  -- SET MONTH END DATE
DECLARE @LAST_MON INT = 20171231;

SELECT EOM.DATE_KEY
	  ,EOM.SRC_TYPE_CD
	  ,EOM.Acct_Nbr
	  ,EOM.[ACCT_OPEN_DT] AS ORIG_DT
	  --,EOM.[BALANCE_SHEET_CATEGORY_CA]
	  ,CASE 
			WHEN EOM.SRC_TYPE_CD = 'AFS' THEN
				   CASE WHEN EOM.[BALANCE_SHEET_CATEGORY_CA] in ('Commercial Real Estate Mtgs','Multifamily Mtgs 5+ Units')
						THEN IIF(IP.[BorGtr_FICO] IS NULL, PL.A15738_MinFICO, IP.[BorGtr_FICO])
				   ELSE  PL.A15738_MinFICO END
			WHEN EOM.SRC_TYPE_CD = 'IL' 
				THEN IIF(LEN(ILORIG.[CRED_BUR_SCORE_CD] ) <1, PL.A15738_MinFICO, TRY_CAST(RTRIM(LTRIM(ILORIG.[CRED_BUR_SCORE_CD]))  AS INT))
			WHEN EOM.SRC_TYPE_CD = 'ML' 
				THEN IIF(LEN(MLORIG.[CHAR_VALUE_AMT]) <1, PL.A15738_MinFICO, TRY_CAST(RTRIM(LTRIM(MLORIG.[CHAR_VALUE_AMT]))  AS INT))
			ELSE PL.A15738_MinFICO
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
						THEN IIF(LEN(ILCURR.[CHAR_VALUE_AMT]) <1, TRY_CAST(RTRIM(LTRIM(ILORIG.[CRED_BUR_SCORE_CD])) AS INT), 
							TRY_CAST(RTRIM(LTRIM(ILCURR.[CHAR_VALUE_AMT])) AS INT))
					 ELSE TRY_CAST(RTRIM(LTRIM(ILCURR.[CHAR_VALUE_AMT])) AS INT) END
			WHEN EOM.SRC_TYPE_CD = 'ML' THEN
				CASE WHEN EOM.[ACCT_OPEN_DT] >= DATEADD(month, DATEDIFF(month, 0, CONVERT(DATE, CONVERT(VARCHAR(20), @DATE_KEY))), 0)
						THEN IIF(MLCURR.[RISK_SCORE] IS NULL 
								,IIF(LEN(MLORIG.[CHAR_VALUE_AMT]) <1, PL.A15738_MinFICO, TRY_CAST(RTRIM(LTRIM(MLORIG.[CHAR_VALUE_AMT])) AS INT))
								,CAST(MLCURR.[RISK_SCORE] AS INT))
					 ELSE CAST(MLCURR.[RISK_SCORE] AS INT) END
			ELSE RDM.FICO_CURR
	   END AS FICO_ORIG

  --INTO #FICO_ALL

  FROM [CreditAdmin].[dbo].[CA_GL_RECONCILED_MAKE_TABLE_CURR] EOM
  
  LEFT JOIN [RDM_Loan].[ADJ].[V_LOAN_GL_RECONCILED_EOM] RDM
	ON RDM.ACCT_NBR = EOM.ACCT_NBR AND RDM.[DATE_KEY] = @LAST_MON --APPEND LAST MONTH FICO CURRENT VALUE
  
  LEFT JOIN [PLProd].[dbo].[vw_powerlender] PL
	ON (PL.A15738_MinFICO<851 AND PL.A15738_MinFICO>299)
	AND PL.A304_CustomerKey =
		CASE WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
			 ELSE RIGHT(EOM.Bisys_Nbr_Fmt,8)
		END
  
  LEFT JOIN [CREMF].[dbo].[CRE_Collateral] IP
    ON right(EOM.Bisys_Nbr_Fmt,8)=IP.[BisysNo_Short] AND (IP.[BorGtr_FICO]<851 AND IP.[BorGtr_FICO] >299)

----==============================ORIGINAL FICO SOURCE================================================================
  LEFT JOIN [EagleVision].[dbo].[V_TVN_ML_USER_DEF_MSTR_REC_CURR] MLORIG 
	ON EOM.ACCT_NBR = CAST(MLORIG.ACCT_NBR AS VARCHAR) AND MLORIG.MSTR_REC_NBR=473
  
  LEFT JOIN [EagleVision].[dbo].[V_TVN_INST_LOAN_ACCT_CURR] ILORIG 
	ON CAST(ILORIG.ACCT_NBR AS VARCHAR) = EOM.ACCT_NBR

----==============================CURRENT FICO SOURCE================================================================

  LEFT JOIN [EagleVision].[dbo].[V_TVN_ML_DELINQ_RECS_CURR] MLCURR 
	ON EOM.ACCT_NBR = CAST(MLCURR.ACCT_NBR AS VARCHAR)

  LEFT JOIN [EagleVision].[dbo].[V_TVN_IL_USER_DEF_MSTR_REC_CURR] ILCURR 
	ON CAST(ILCURR.ACCT_NBR AS VARCHAR) = EOM.ACCT_NBR AND ILCURR.[MSTR_REC_NBR] = 720
  
 -- LEFT JOIN [PLProd].[dbo].[vw_LoanFacts] PLF
	--ON PLF.Loan_Key =
	--	CASE 
	--	WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
	--		 THEN LEFT(EOM.Bisys_Nbr_Fmt,2) + '-0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
	--	ELSE 
	--		 EOM.Bisys_Nbr_Fmt
	--	END
  
  LEFT JOIN [PLProd_EMPLOYEE].[dbo].[VW_LOAN_FACT_EMP_CUSO] EMP
	ON (EMP.FICO<851 AND EMP.FICO>299)
	AND EMP.[Customer_key] =
		CASE WHEN SUBSTRING(EOM.Bisys_Nbr_Fmt,4,1)='7'
			 THEN '0' + SUBSTRING(EOM.Bisys_Nbr_Fmt,4,6) + RIGHT(EOM.Bisys_Nbr_Fmt,1)
			 ELSE RIGHT(EOM.Bisys_Nbr_Fmt,8)
		END

  WHERE EOM.Date_Key=@DATE_KEY AND EOM.SRC_TYPE_CD in ('AFS','ML','IL') 
  --AND Status_Description='OPEN'
  --AND ((PL.A15738_MinFICO<950 AND PL.A15738_MinFICO>300) OR (IP.[BorGtr_FICO]<950 AND IP.[BorGtr_FICO] >300))
  --ORDER BY SRC_TYPE_CD, Balance_Sheet_Category, ORIG_LTV DESC
   
 
------================UPDATE CURRENT AND ORIGINAL FICO=====================
-- -- 	UPDATE A
--	--SET A.[FICO_CURR] = FICO.[FICO_CURR], A.FICO_ORIG = FICO.FICO_ORIG
--	--FROM #ALL A
--	--LEFT JOIN [SB_PA_Margaret].[FRB\mlan].[V_FICO_EOM] FICO ON FICO.[ACCT_NBR] = A.[ACCT_NBR]
--	--WHERE FICO.[FICO_CURR] IS NOT NULL;


--------========== UPDATE INVALID FICO TO NULL==============
--	UPDATE #ALL
--	SET #ALL.FICO_ORIG = NULL
--	FROM #ALL 
--	WHERE #ALL.FICO_ORIG <300 OR #ALL.FICO_ORIG >850 OR #ALL.FICO_ORIG= 0;

--	UPDATE #ALL
--	SET #ALL.FICO_CURR = NULL
--	FROM #ALL 
--	WHERE #ALL.FICO_CURR <300 OR #ALL.FICO_CURR >850 OR #ALL.FICO_CURR = 0;

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
*/