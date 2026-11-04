"""Rule-fixed I-A common-base helpers; no action at import."""  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
from pathlib import Path  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
import json  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
import numpy as np  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
import pandas as pd  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
import rescue_switch  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
ROOT=Path(__file__).resolve().parents[2]  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
CTCONFIG=ROOT/'02_code/00_common/01_UN_Comtrade/config'  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def crosswalk(frame, availability=False):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x=frame.copy()  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    rules=pd.read_csv(CTCONFIG/'special_area_crosswalk.csv')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    expected=['comtrade_code','iso3','applies_to','source_url','quote']  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if list(rules)!=expected or rules.duplicated(['comtrade_code','applies_to']).any():  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        raise ValueError('C02 invalid shared crosswalk schema/key')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if not rules.applies_to.isin(['reporter','partner','availability']).all():  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        raise ValueError('C02 invalid crosswalk role')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    roles=[('availability','reporter_code','reporter_iso')] if availability else [('reporter','reporterCode','reporterISO'),('partner','partnerCode','partnerISO')]  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    for role,code,iso in roles:  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        mapping=rules.loc[rules.applies_to.eq(role)].set_index('comtrade_code').iso3  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        source=('reporter_iso_source' if role in ['reporter','availability'] else 'partner_iso_source')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        flag=('comtrade_490_reporter' if role in ['reporter','availability'] else 'comtrade_490_partner')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        x[source]=x[iso]  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        x[flag]=x[code].eq(490).astype('int8')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        x[iso]=x[code].map(mapping).fillna(x[iso])  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if availability:  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        if x.duplicated(['year','reporter_iso']).any():raise ValueError('C02 reporter158/490 availability collision; no priority or summing')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    else:  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        country=x.reporterISO.str.fullmatch('[A-Z]{3}')&x.partnerISO.str.fullmatch('[A-Z]{3}')&~x.reporterCode.isin([97,975])&x.reporterISO.ne(x.partnerISO)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        if x.loc[country].duplicated(['refYear','reporterISO','partnerISO']).any():raise ValueError('C02 canonical158/490 collision; no priority or summing')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    return x  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def add_product_variants(out,raw,idx):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    extra=raw.loc[raw.cmdCode.eq('490700')].groupby(idx,dropna=False).primaryValue.sum().rename('v_4907_usd').reset_index()  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    out=out.merge(extra,on=idx,how='left',validate='1:1')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    out['v_4907_usd']=out.v_4907_usd.fillna(0.)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    return out  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def finish_product_variants(out,diag):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    out['v_4907_k']=out.v_4907_usd/1000.  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    out['ttl_ex8523_lb_k']=out.v_3706_k+out.v_49_k+out.v_97_k  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    out['ttl_ex8523_ub_k']=out.ttl_ex8523_lb_k  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    out['ttl_ex8523']=out.ttl_ex8523_lb_k  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    labels=pd.read_csv(CTCONFIG/'product_definition_H3.csv',dtype={'canonical_H3_code':str})  # RESCUE C10
    overrides=pd.read_csv(CTCONFIG/'product_label_overrides_C10.csv',dtype={'canonical_H3_code':str})  # RESCUE C10
    labels=labels.merge(overrides,on=['canonical_H3_code','analysis_category'],how='left',validate='1:1')  # RESCUE C10
    if labels[['display_label','scope_note']].isna().any().any():raise ValueError('C10 incomplete label overrides')  # RESCUE C10
    labels[['canonical_H3_code','analysis_category','display_label','scope_note']].to_csv(diag/'rescue_C10_product_scope.csv',index=False)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    return out  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def apply_rta_overrides(existing,config,diag):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    rules=pd.read_csv(config/'rta_overrides.csv')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    key=['year','iso3_o','iso3_d']  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if rules.duplicated(key+['variable']).any() or not rules.variable.eq('fta_wto').all():raise ValueError('C03 invalid override key/variable')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if not rules.rule_id.eq('C03').all():raise ValueError('C03 unexpected rule id')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    lookup=existing.set_index(key)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    ri=pd.MultiIndex.from_frame(rules[key])  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if not ri.isin(lookup.index).all():raise ValueError('C03 override key absent from source')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if not np.array_equal(lookup.loc[ri,'fta_wto'].to_numpy(),rules.old_value.to_numpy()):raise ValueError('C03 old-value mismatch')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x=existing.copy();x['fta_wto_source']=x.fta_wto  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    changes=rules.set_index(key).new_value.reindex(pd.MultiIndex.from_frame(x[key]))  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    use=changes.notna().to_numpy();x.loc[use,'fta_wto']=changes.loc[changes.notna()].to_numpy()  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    rules.to_csv(diag/'rescue_C03_applied_overrides.csv',index=False)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    return x  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def export_fta_discordance(g,diag):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    mask=~(g.fta_wto.eq(g.fta_wto_raw)|(g.fta_wto.isna()&g.fta_wto_raw.isna()))  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x=g.loc[mask].copy()  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    for var in ['fta_wto','fta_wto_raw']:  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        z=g.loc[g[var].eq(1)].groupby(['iso3_o','iso3_d']).year.agg(['min','max'])  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        z=z.rename(columns={'min':var+'_first1','max':var+'_last1'})  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        x=x.merge(z,on=['iso3_o','iso3_d'],how='left',validate='m:1')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x['discordance_direction']=np.where(x.fta_wto.eq(1),'supplemented_only','raw_only')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x['pattern']='interior_gap_or_different_treatment_object'  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    for own,other,prefix in [('fta_wto','fta_wto_raw','supplemented'),('fta_wto_raw','fta_wto','raw')]:  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        on=x[own].eq(1)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        x.loc[on&x.year.lt(x[other+'_first1']),'pattern']=prefix+'_earlier_start'  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        x.loc[on&x.year.gt(x[other+'_last1']),'pattern']=prefix+'_later_end'  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        x.loc[on&x[other+'_first1'].isna(),'pattern']=prefix+'_only_whole_observed_support'  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    proven=(x.iso3_o.eq('ROU')&x.eu_d.eq(1)|x.iso3_d.eq('ROU')&x.eu_o.eq(1))&x.iso3_o.ne(x.iso3_d)&x.fta_wto.eq(0)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x['decision']=np.where(proven,'CORRECT via C03','NOT-CORRECTED (owner)')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x['correction_id']=np.where(proven,'C03','')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x['proposed_fta_wto']=x.fta_wto.where(~proven,1)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x['rta_coverage_raw_label']=x.rta_coverage.map({1:'Goods',2:'Goods & Services',3:'Services'}).fillna('')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x['rta_type_raw_label']=x.rta_type.map({1:'CU',2:'CU & EIA',3:'EIA',4:'FTA',5:'FTA & EIA',6:'PSA',7:'PSA & EIA'}).fillna('')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x.sort_values(['year','iso3_o','iso3_d'],kind='stable').to_csv(diag/'rescue_C05_fta_discordance.csv',index=False)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    x.groupby(['pattern','decision']).size().rename('rows').reset_index().to_csv(diag/'rescue_C05_pattern_counts.csv',index=False)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    g.loc[g.rta_coverage.eq(3)].to_csv(diag/'rescue_C05_raw_labeled_services.csv',index=False)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    (diag/'rescue_C05_definition_note.json').write_text(json.dumps({'field_used':'fta_wto for all coverage/types; C03 is separately switched','raw_coverage_labels':{'1':'Goods','2':'Goods & Services','3':'Services'},'documentation_conflict':'CEPII2023 p28 reverses descriptions of2 and3; no recode','discordant_rows':len(x),'C03_proven_discordances':int(proven.sum()),'other_values_unchanged':int((~proven).sum()),'raw_labeled_services_rows':int(g.rta_coverage.eq(3).sum())},indent=2))  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def base_availability_extra(av,availability):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    cols=['year','reporter_iso','reporter_code']  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    for c in ['reporter_iso_source','comtrade_490_reporter']:  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        if c in availability:cols.append(c)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    extras=availability[cols].rename(columns={'reporter_iso':'iso3_d','reporter_code':'comtrade_reporter_code','reporter_iso_source':'comtrade_reporter_iso_src'})  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    return av.merge(extras,on=['year','iso3_d'],how='left',validate='1:1')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def base_territory_flags(base,availability,trade):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    counts=trade.groupby(['year','reporter_code']).size().rename('basket_rows').reset_index()  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    av=availability.merge(counts,on=['year','reporter_code'],how='left',validate='1:1')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    av['zero_fill_no_rows']=av.trade_reporting_available.eq(1)&av.basket_rows.isna()  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    z=av[['year','reporter_iso','zero_fill_no_rows']].rename(columns={'reporter_iso':'iso3_d'})  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    base=base.merge(z,on=['year','iso3_d'],how='left',validate='m:1')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    base['zero_fill_no_rows']=base.zero_fill_no_rows.fillna(False).astype('int8')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    base['territory_france_251_o']=base.iso3_o.eq('FRA').astype('int8')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    base['territory_france_251_d']=base.iso3_d.eq('FRA').astype('int8')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    base['territory_partner_492']=base.comtrade_partner_code.eq(492).astype('int8')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    base['territory_mco_guf_pair']=(base.iso3_o.isin(['MCO','GUF'])|base.iso3_d.isin(['MCO','GUF'])).astype('int8')  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    return base  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10

def write_base_rescue_diagnostics(base,diag):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    cols=['year','iso3_d']  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
    if rescue_switch.enabled('C09'):  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        base.loc[base.zero_fill_no_rows.eq(1),cols+['comtrade_reporter_code']].groupby(cols+['comtrade_reporter_code'],dropna=False).size().rename('base_rows').reset_index().to_csv(diag/'rescue_C09_zero_fill_no_rows.csv',index=False)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
        base[['year','iso3_o','iso3_d','territory_france_251_o','territory_france_251_d','territory_partner_492','territory_mco_guf_pair']].to_csv(diag/'rescue_C09_territory_flags.csv',index=False)  # RESCUE C02; RESCUE C03; RESCUE C05; RESCUE C09; RESCUE C10
