# IMC batch: merge every regression run, write reports to logs/
# IMC resolves a relative -out under cov_work/, so every output path is absolute
merge cov_work/mc/mc_* -out [pwd]/cov_work/merged -overwrite
load -run [pwd]/cov_work/merged
report -summary -out [pwd]/logs/cov_summary.rpt
report -detail -metrics covergroup -out [pwd]/logs/cov_covergroups.rpt
report -detail -metrics assertion -out [pwd]/logs/cov_assertions.rpt
exit
