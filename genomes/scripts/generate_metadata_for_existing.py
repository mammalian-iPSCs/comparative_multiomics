#!/usr/bin/env python3
"""
Generate genome_metadata.tsv for all existing assemblies in refgenie.

Cross-references:
  - genome_config.yaml (aliases, genome_description, assets)
  - input_files/fasta_list.csv (genome source paths with accessions)
  - input_files/gtf_list.csv (TOGA annotation source paths)
  - TOGA v1 overview.table.tsv (if available, for species/taxonomy info)

Run from the genomes/ directory.
"""

import csv
import re
import sys
from pathlib import Path
from datetime import date

# Paths
GENOMES_DIR = Path(__file__).resolve().parent.parent
CONFIG_FILE = GENOMES_DIR / "genome_config.yaml"
FASTA_LIST = GENOMES_DIR / "input_files" / "fasta_list.csv"
GTF_LIST = GENOMES_DIR / "input_files" / "gtf_list.csv"
OUTPUT_FILE = GENOMES_DIR / "genome_metadata.tsv"

# Metadata columns
COLUMNS = [
    "assembly_name", "species", "common_name", "accession", "taxonomy_id",
    "lineage", "genome_source", "annotation_source", "annotation_reference",
    "date_added"
]

TODAY = date.today().isoformat()


def parse_aliases_from_config(config_path):
    """Extract all aliases from genome_config.yaml (simple regex, no YAML parser needed)."""
    aliases = []
    text = config_path.read_text()
    # Find alias blocks: "aliases:\n     - NAME"
    for match in re.finditer(r'aliases:\s*\n\s*-\s*(\S+)', text):
        aliases.append(match.group(1))
    return aliases


def parse_genome_descriptions(config_path):
    """Extract genome_description per hash block, map to aliases."""
    text = config_path.read_text()
    descriptions = {}
    current_hash = None
    current_aliases = []
    current_desc = None

    for line in text.splitlines():
        # New hash block
        hash_match = re.match(r'  ([0-9a-f]{48}):', line)
        if hash_match:
            # Save previous
            if current_aliases and current_desc:
                for a in current_aliases:
                    descriptions[a] = current_desc
            current_hash = hash_match.group(1)
            current_aliases = []
            current_desc = None
            continue

        alias_match = re.match(r'\s+-\s+(\S+)', line)
        if alias_match and current_hash:
            current_aliases.append(alias_match.group(1))

        desc_match = re.match(r'\s+genome_description:\s*(.+)', line)
        if desc_match and current_hash:
            current_desc = desc_match.group(1).strip()

    # Last block
    if current_aliases and current_desc:
        for a in current_aliases:
            descriptions[a] = current_desc

    return descriptions


def parse_assets_from_config(config_path):
    """Determine which assets each alias has."""
    text = config_path.read_text()
    alias_assets = {}
    current_aliases = []
    current_assets = set()
    in_assets = False

    for line in text.splitlines():
        hash_match = re.match(r'  ([0-9a-f]{48}):', line)
        if hash_match:
            # Save previous
            for a in current_aliases:
                alias_assets[a] = current_assets
            current_aliases = []
            current_assets = set()
            in_assets = False
            continue

        alias_match = re.match(r'\s+-\s+(\S+)', line)
        if alias_match:
            current_aliases.append(alias_match.group(1))

        if re.match(r'\s+assets:', line):
            in_assets = True
            continue

        if in_assets:
            asset_match = re.match(r'\s{6}(\w+):', line)
            if asset_match:
                current_assets.add(asset_match.group(1))

    # Last block
    for a in current_aliases:
        alias_assets[a] = current_assets

    return alias_assets


def parse_fasta_list(fasta_list_path):
    """Parse fasta_list.csv to extract genome source info."""
    sources = {}
    if not fasta_list_path.exists():
        return sources

    with open(fasta_list_path) as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 2:
                continue
            path, alias = row[0].strip(), row[1].strip()
            if alias == "species_name":
                continue

            # Extract accession from path
            accession_match = re.search(r'(GC[AF]_\d+\.\d+)', path)
            accession = accession_match.group(1) if accession_match else ""

            # Determine source type
            if "T2T_primates" in path:
                source = f"T2T primates ({Path(path).name})"
            elif "DNAZoo" in path:
                source = f"DNA Zoo ({Path(path).name})"
            elif "other/loxAfr4" in path:
                source = f"Broad Institute (loxAfr4)"
            elif accession:
                source = f"NCBI ({accession})"
            else:
                source = path

            sources[alias] = {"path": path, "accession": accession, "source": source}

    return sources


def parse_gtf_list(gtf_list_path):
    """Parse gtf_list.csv to extract annotation source info."""
    sources = {}
    if not gtf_list_path.exists():
        return sources

    with open(gtf_list_path) as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 2:
                continue
            alias, path = row[0].strip(), row[1].strip()

            # Extract TOGA directory info
            toga_match = re.search(
                r'TOGA/human_hg38_reference/(\w+)/([^/]+)', path
            )
            if toga_match:
                order = toga_match.group(1)
                species_dir = toga_match.group(2)
                # Extract assembly from dir name
                parts = species_dir.split("__")
                toga_assembly = parts[-1] if parts else ""
                sources[alias] = {
                    "path": path,
                    "order": order,
                    "species_dir": species_dir,
                    "toga_assembly": toga_assembly,
                    "source": f"TOGA v1 ({path})"
                }
            else:
                sources[alias] = {
                    "path": path,
                    "source": f"local ({path})"
                }

    return sources


def species_from_alias(alias):
    """Derive species name from alias like Panthera_leo_TOGA -> Panthera leo."""
    name = alias
    # Remove known suffixes
    for suffix in ["_TOGA", "_T2Tv2", "_RheMac10"]:
        name = name.replace(suffix, "")
    return name.replace("_", " ")


# Known metadata for non-TOGA reference genomes
KNOWN_GENOMES = {
    "hg38": {
        "species": "Homo sapiens",
        "common_name": "human",
        "accession": "GCA_000001405.15",
        "taxonomy_id": "9606",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "NCBI (GRCh38_no_alt_analysis_set)",
        "annotation_source": "GENCODE",
        "annotation_reference": "hg38",
    },
    "hg38_primary": {
        "species": "Homo sapiens",
        "common_name": "human",
        "accession": "GCA_000001405.15",
        "taxonomy_id": "9606",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "NCBI (GRCh38 primary assembly)",
        "annotation_source": "",
        "annotation_reference": "hg38",
    },
    "mm10": {
        "species": "Mus musculus",
        "common_name": "house mouse",
        "accession": "GCA_000001635.5",
        "taxonomy_id": "10090",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Glires; Rodentia",
        "genome_source": "NCBI (mm10 seqs_for_alignment_pipelines)",
        "annotation_source": "GENCODE",
        "annotation_reference": "mm10",
    },
    "EBV": {
        "species": "Human gammaherpesvirus 4",
        "common_name": "Epstein-Barr virus",
        "accession": "NC_007605.1",
        "taxonomy_id": "10376",
        "lineage": "Viruses; Herpesviridae; Gammaherpesvirinae",
        "genome_source": "NCBI",
        "annotation_source": "",
        "annotation_reference": "",
    },
    "ercc": {
        "species": "ERCC spike-in controls",
        "common_name": "ERCC",
        "accession": "",
        "taxonomy_id": "",
        "lineage": "",
        "genome_source": "ThermoFisher ERCC spike-in sequences",
        "annotation_source": "",
        "annotation_reference": "",
    },
    "Bos_taurus": {
        "species": "Bos taurus",
        "common_name": "cattle",
        "accession": "GCF_002263795.3",
        "taxonomy_id": "9913",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Laurasiatheria; Ruminantia",
        "genome_source": "NCBI (ARS-UCD2.0)",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "Callithrix_jacchus": {
        "species": "Callithrix jacchus",
        "common_name": "common marmoset",
        "accession": "GCF_009663435.1",
        "taxonomy_id": "9483",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "NCBI (Callithrix_jacchus_cj1700_1.1)",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "Gallus_gallus": {
        "species": "Gallus gallus",
        "common_name": "chicken",
        "accession": "GCF_016699485.2",
        "taxonomy_id": "9031",
        "lineage": "Aves; Neognathae; Galliformes; Phasianidae; Gallus",
        "genome_source": "NCBI (bGalGal1.mat.broiler.GRCg7b)",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "Notamacropus_eugeni": {
        "species": "Notamacropus eugenii",
        "common_name": "tammar wallaby",
        "accession": "GCA_000004035.1",
        "taxonomy_id": "9315",
        "lineage": "Mammalia; Theria; Metatheria; Diprotodontia; Macropodidae",
        "genome_source": "NCBI",
        "annotation_source": "Ensembl",
        "annotation_reference": "",
    },
    "Anolis_carolinensis": {
        "species": "Anolis carolinensis",
        "common_name": "green anole",
        "accession": "GCF_000090745.1",
        "taxonomy_id": "28377",
        "lineage": "Reptilia; Squamata; Iguania; Dactyloidae; Anolis",
        "genome_source": "NCBI (AnoCar2.0)",
        "annotation_source": "Ensembl",
        "annotation_reference": "",
    },
    "Panthera_leo": {
        "species": "Panthera leo",
        "common_name": "lion",
        "accession": "GCA_008795835.1",
        "taxonomy_id": "9689",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Laurasiatheria; Carnivora",
        "genome_source": "NCBI (GCA_008795835.1)",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "Caretta_caretta": {
        "species": "Caretta caretta",
        "common_name": "loggerhead sea turtle",
        "accession": "GCF_023653815.1",
        "taxonomy_id": "8144",
        "lineage": "Reptilia; Testudines; Cheloniidae; Caretta",
        "genome_source": "NCBI",
        "annotation_source": "NCBI",
        "annotation_reference": "",
    },
    "Bombina_bombina": {
        "species": "Bombina bombina",
        "common_name": "fire-bellied toad",
        "accession": "GCA_027579735.1",
        "taxonomy_id": "8329",
        "lineage": "Amphibia; Anura; Bombinatoridae; Bombina",
        "genome_source": "NCBI",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "Loxodonta_africana": {
        "species": "Loxodonta africana",
        "common_name": "African savanna elephant",
        "accession": "GCF_009858635.2",
        "taxonomy_id": "9785",
        "lineage": "Mammalia; Theria; Eutheria; Afrotheria; Proboscidea; Elephantidae",
        "genome_source": "NCBI",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "Equus_caballus": {
        "species": "Equus caballus",
        "common_name": "horse",
        "accession": "GCF_002863925.1",
        "taxonomy_id": "9796",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Laurasiatheria; Perissodactyla",
        "genome_source": "NCBI (EquCab3.0)",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "Canis_lupus": {
        "species": "Canis lupus familiaris",
        "common_name": "dog",
        "accession": "GCF_011100685.1",
        "taxonomy_id": "9615",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Laurasiatheria; Carnivora",
        "genome_source": "NCBI (UU_Cfam_GSD_1.0)",
        "annotation_source": "NCBI/Ensembl",
        "annotation_reference": "",
    },
    "GorGor1": {
        "species": "Gorilla gorilla",
        "common_name": "western gorilla",
        "accession": "",
        "taxonomy_id": "9593",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "GorGor1 assembly",
        "annotation_source": "",
        "annotation_reference": "",
    },
    "Pan_troglodytes_T2Tv2": {
        "species": "Pan troglodytes",
        "common_name": "chimpanzee",
        "accession": "mPanTro3",
        "taxonomy_id": "9598",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "T2T primates (mPanTro3.pri.cur.20231031.fasta.gz)",
        "annotation_source": "GENCODE/T2T",
        "annotation_reference": "",
    },
    "Pongo_pygmaeus_T2Tv2": {
        "species": "Pongo pygmaeus",
        "common_name": "Bornean orangutan",
        "accession": "mPonPyg2",
        "taxonomy_id": "9600",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "T2T primates (mPonPyg2.pri.cur.20231031.fasta.gz)",
        "annotation_source": "GENCODE/T2T",
        "annotation_reference": "",
    },
    "Gorilla_gorilla_T2Tv2": {
        "species": "Gorilla gorilla",
        "common_name": "western gorilla",
        "accession": "mGorGor1",
        "taxonomy_id": "9593",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "T2T primates (mGorGor1.pri.cur.20231031.fasta.gz)",
        "annotation_source": "GENCODE/T2T",
        "annotation_reference": "",
    },
    "Pongo_abelii_T2Tv2": {
        "species": "Pongo abelii",
        "common_name": "Sumatran orangutan",
        "accession": "mPonAbe2",
        "taxonomy_id": "9601",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "T2T primates (mPonAbe2)",
        "annotation_source": "GENCODE/T2T",
        "annotation_reference": "",
    },
    "Macaca_mullatta_RheMac10": {
        "species": "Macaca mulatta",
        "common_name": "rhesus macaque",
        "accession": "GCF_003339765.1",
        "taxonomy_id": "9544",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "NCBI (Mmul_10/rheMac10)",
        "annotation_source": "GENCODE/NCBI",
        "annotation_reference": "",
    },
    "Pongo_pygmaeus": {
        "species": "Pongo pygmaeus",
        "common_name": "Bornean orangutan",
        "accession": "",
        "taxonomy_id": "9600",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "NCBI/Ensembl",
        "annotation_source": "Ensembl",
        "annotation_reference": "",
    },
    "Pan_troglodytes": {
        "species": "Pan troglodytes",
        "common_name": "chimpanzee",
        "accession": "",
        "taxonomy_id": "9598",
        "lineage": "Mammalia; Theria; Eutheria; Boreoeutheria; Euarchontoglires; Primates",
        "genome_source": "NCBI/Ensembl",
        "annotation_source": "Ensembl",
        "annotation_reference": "",
    },
}

# TOGA v1 assemblies: alias -> (TOGA assembly ID, NCBI accession from fasta_list)
TOGA_ASSEMBLIES = {
    "Panthera_tigris_TOGA":             {"assembly": "HLpanTig3",  "accession": "GCF_000464555.1",  "species": "Panthera tigris",                 "common_name": "tiger",                    "order": "Carnivora"},
    "Lutra_lutra_TOGA":                 {"assembly": "HLlutLut2",  "accession": "GCA_902655055.1",  "species": "Lutra lutra",                     "common_name": "European otter",           "order": "Carnivora"},
    "Mustela_putorius_TOGA":            {"assembly": "HLmusPut1",  "accession": "GCA_902460205.1",  "species": "Mustela putorius",                "common_name": "European polecat",         "order": "Carnivora"},
    "Equus_caballus_TOGA":              {"assembly": "HLequCab4",  "accession": "GCF_002863925.1",  "species": "Equus caballus",                  "common_name": "horse",                    "order": "Perissodactyla"},
    "Bos_grunniens_TOGA":               {"assembly": "HLbosGru2",  "accession": "GCA_005887515.2",  "species": "Bos grunniens",                   "common_name": "domestic yak",             "order": "Ruminantia"},
    "Muntiacus_reevesi_TOGA":           {"assembly": "HLmunRee1",  "accession": "GCA_008787405.1",  "species": "Muntiacus reevesi",               "common_name": "Chinese muntjac",          "order": "Ruminantia"},
    "Callithrix_jacchus_TOGA":          {"assembly": "HLcalJac4",  "accession": "GCA_011100555.1",  "species": "Callithrix jacchus",              "common_name": "common marmoset",          "order": "Primates"},
    "Panthera_leo_TOGA":                {"assembly": "HLpanLeo2",  "accession": "GCA_008795835.1",  "species": "Panthera leo",                    "common_name": "lion",                     "order": "Carnivora"},
    "Papio_anubis_TOGA":                {"assembly": "HLpapAnu5",  "accession": "GCA_008728515.1",  "species": "Papio anubis",                    "common_name": "olive baboon",             "order": "Primates"},
    "Oryctolagus_cuniculus_TOGA":        {"assembly": "HLoryCun3",  "accession": "GCA_009806435.1",  "species": "Oryctolagus cuniculus",           "common_name": "rabbit",                   "order": "Lagomorpha"},
    "Hydrochoerus_hydrochaeris_TOGA":    {"assembly": "HLhydHyd1",  "accession": "GCA_004027455.1",  "species": "Hydrochoerus hydrochaeris",       "common_name": "capybara",                 "order": "Rodentia"},
    "Zalophus_californianus_TOGA":       {"assembly": "HLzalCal1",  "accession": "GCA_009762305.1",  "species": "Zalophus californianus",          "common_name": "California sea lion",      "order": "Carnivora"},
    "Hippopotamus_amphibius_TOGA":       {"assembly": "HLhipAmp3",  "accession": "GCA_004027065.2",  "species": "Hippopotamus amphibius",          "common_name": "hippopotamus",             "order": "Whippomorpha"},
    "Procavia_capensis_TOGA":            {"assembly": "HLproCap4",  "accession": "GCA_004026925.2",  "species": "Procavia capensis",               "common_name": "Cape rock hyrax",          "order": "Afrotheria"},
    "Dolichotis_patagonum_TOGA":         {"assembly": "HLdolPat1",  "accession": "GCA_004027295.1",  "species": "Dolichotis patagonum",            "common_name": "Patagonian mara",          "order": "Rodentia"},
    "Pan_troglodytes_TOGA":              {"assembly": "HLpanTro7",  "accession": "mPanTro3 (T2T)",   "species": "Pan troglodytes",                 "common_name": "chimpanzee",               "order": "Primates"},
    "Pongo_pygmaeus_TOGA":               {"assembly": "HLponPyg3",  "accession": "mPonPyg2 (T2T)",   "species": "Pongo pygmaeus",                  "common_name": "Bornean orangutan",        "order": "Primates"},
    "Loxodonta_africana_TOGA":           {"assembly": "HLloxAfr4",  "accession": "loxAfr4 (Broad)",  "species": "Loxodonta africana",              "common_name": "African savanna elephant", "order": "Afrotheria"},
    "Gorilla_gorilla_TOGA":              {"assembly": "HLgorGor7",  "accession": "mGorGor1 (T2T)",   "species": "Gorilla gorilla",                 "common_name": "western gorilla",          "order": "Primates"},
    "Equus_quagga_TOGA":                 {"assembly": "HLequQua1",  "accession": "DNA Zoo",           "species": "Equus quagga",                    "common_name": "plains zebra",             "order": "Perissodactyla"},
    "Hystrix_cristata_TOGA":             {"assembly": "HLhysCri1",  "accession": "GCA_004026905.1",  "species": "Hystrix cristata",                "common_name": "crested porcupine",        "order": "Rodentia"},
}


def main():
    print(f"Parsing {CONFIG_FILE} ...")
    aliases = parse_aliases_from_config(CONFIG_FILE)
    descriptions = parse_genome_descriptions(CONFIG_FILE)
    alias_assets = parse_assets_from_config(CONFIG_FILE)

    print(f"Found {len(aliases)} aliases")
    print(f"Parsing source lists ...")
    fasta_sources = parse_fasta_list(FASTA_LIST)
    gtf_sources = parse_gtf_list(GTF_LIST)

    rows = []

    for alias in sorted(aliases):
        assets = alias_assets.get(alias, set())
        has_toga_gtf = "toga_gtf" in assets
        has_gencode_gtf = "gencode_gtf" in assets

        # Check if it's a known non-TOGA genome
        if alias in KNOWN_GENOMES:
            info = KNOWN_GENOMES[alias]
            rows.append({
                "assembly_name": alias,
                "species": info["species"],
                "common_name": info["common_name"],
                "accession": info["accession"],
                "taxonomy_id": info["taxonomy_id"],
                "lineage": info["lineage"],
                "genome_source": info["genome_source"],
                "annotation_source": info["annotation_source"],
                "annotation_reference": info["annotation_reference"],
                "date_added": TODAY,
            })
        # Check if it's a TOGA assembly
        elif alias in TOGA_ASSEMBLIES:
            info = TOGA_ASSEMBLIES[alias]
            fasta_info = fasta_sources.get(alias, {})
            gtf_info = gtf_sources.get(alias, {})

            genome_source = fasta_info.get("source", f"NCBI ({info['accession']})")
            annotation_source = gtf_info.get("source", f"TOGA v1 (human_hg38_reference/{info['order']}/)")

            rows.append({
                "assembly_name": alias,
                "species": info["species"],
                "common_name": info["common_name"],
                "accession": info["accession"],
                "taxonomy_id": "",
                "lineage": f"Mammalia; {info['order']}",
                "genome_source": genome_source,
                "annotation_source": annotation_source,
                "annotation_reference": "human_hg38_reference",
                "date_added": TODAY,
            })
        else:
            # Unknown — fill in what we can
            species = species_from_alias(alias)
            desc = descriptions.get(alias, "")
            rows.append({
                "assembly_name": alias,
                "species": species,
                "common_name": "",
                "accession": "",
                "taxonomy_id": "",
                "lineage": "",
                "genome_source": desc if desc else "unknown",
                "annotation_source": "gencode_gtf" if has_gencode_gtf else ("toga_gtf" if has_toga_gtf else ""),
                "annotation_reference": "",
                "date_added": TODAY,
            })

    # Write output
    with open(OUTPUT_FILE, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)

    print(f"\nWrote {len(rows)} entries to {OUTPUT_FILE}")
    print("Columns:", "\t".join(COLUMNS))


if __name__ == "__main__":
    main()
