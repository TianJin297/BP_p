###
# This script is meant to run the best practice pipeline with original 
# bwa and gatk
####

# set file pathes
bwa_org=/curr/tianj/tools/bwa-org
gatk4=/curr/tianj/tools/gatk4_ori.jar
gatk3=/curr/tianj/tools/gatk3_ori.jar
samtools=/curr/tianj/tools/samtools
picard=/curr/tianj/tools/picard.jar
java=/usr/bin/java
bcftools=/curr/tianj/tools/bcftools
bgzip=/curr/tianj/tools/bgzip
tabix=/curr/tianj/tools/tabix

# set environment variables
mem_pp=4
cpus=64

# set input and output file pathes
fastq1=$1
fastq2=$2
work_dir=$3
sp_name=$4 # sample name
platform=Illumina
ref=/local/ref/human_g1k_v37.fasta
dbsnp=/local/ref/dbsnp_138.b37.vcf
chr=/curr/tianj/chrs # chr list
beds=/curr/tianj/bedss # bed files one for each chr

$bwa_org mem \
-K 2500000 \
-t $cpus \
-Y \
-R"@RG\tID:${sp_name}\tLB:${sp_name}\tSM:${sp_name}\tPL:$platform" \
$ref \
$fastq1 \
$fastq2 \
2> $work_dir/bwa.log \
| \
$samtools sort \
-m ${mem_pp}G \
-@ $cpus \
-l 1 \
- \
2> $work_dir/sort.log \
> $work_dir/${sp_name}.sort.bam

$samtools index \
-@ $cpus \
$work_dir/${sp_name}.sort.bam

for i in `cat ~/chrs`
do
$samtools view -bh \
-@ $cpus \
$work_dir/${sp_name}.sort.bam \
$i \
> $work_dir/test.${i}.bam
done

for i in `cat ~/chrs`
do
$samtools index \
-@ 2 \
$work_dir/test.${i}.bam \
&& \
/usr/bin/java \
-XX:+UseSerialGC \
-Xmx${mem_pp}g \
-jar $picard \
MarkDuplicates \
INPUT=$work_dir/test.${i}.bam \
OUTPUT=$work_dir/test.${i}.md.bam \
METRICS_FILE=$work_dir/test.${i}.md.matrix \
TMP_DIR=$work_dir/temp \
COMPRESSION_LEVEL=5 \
REMOVE_DUPLICATES=false \
ASSUME_SORTED=true \
VALIDATION_STRINGENCY=SILENT \
2>$work_dir/test.${i}.md.log \
&& \
$samtools index -@ 2 $work_dir/test.${i}.md.bam \
&& \
$java \
-d64 \
-Xmx${mem_pp}g \
-jar $gatk4 \
BaseRecalibrator \
-R $ref \
-I $work_dir/test.${i}.md.bam \
-L $beds/test.${i}.bed \
--known-sites $dbsnp \
--output $work_dir/test.${i}.bqsr.table \
2>$work_dir/test.${i}.bqsr.errlog \
&& \
$java \
-d64 \
-Xmx${mem_pp}g \
-jar $gatk4 \
ApplyBQSR \
-I $work_dir/test.${i}.md.bam \
-L $beds/test.${i}.bed \
--output $work_dir/test.${i}.bqsr.bam \
--bqsr-recal-file $work_dir/test.${i}.bqsr.table \
2>$work_dir/test.${i}.applybqsr.errlog \
&& \
$java \
-d64 \
-Xmx${mem_pp}g \
-jar $gatk4 \
HaplotypeCaller \
-R $ref \
-I $work_dir/test.${i}.bqsr.bam \
-L $beds/test.${i}.bed \
--output $work_dir/test.${i}.htc.vcf \
--emit-ref-confidence=NONE \
2>$work_dir/test.${i}.htc.errlog &

while :; do
  background=( $(jobs -p))
  if (( ${#background[@]} < $cpus-10 )); then
    break
  fi
  sleep 100
done
done

wait
$bcftools concat $work_dir/test.*.htc.vcf -o $work_dir/${sp_name}.vcf
$bgzip $work_dir/${sp_name}.vcf
$tabix $work_dir/${sp_name}.vcf.gz

