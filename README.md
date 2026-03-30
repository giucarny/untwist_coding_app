# Manifesto Gender Analysis (MGA) Annotation App

## Overview

This application is a **Shiny app written in R** for annotating text data stored in a CSV file. It allows the user to:

- load a CSV dataset;
- display one text item at a time;
- optionally display contextual information alongside the text;
- code whether the item is a valid sentence;
- assign a **primary topic**;
- optionally assign a **second topic**;
- code **uncertainty**;
- code **stance**;
- code whether the text is **policy-related**;
- save final annotations or drafts;
- review all annotations in a table;
- export the annotated dataset as a CSV file.

The app is suited for structured manual annotation workflows in which each row of a CSV file represents one unit to be coded.

---

## System requirements

To use the app, the user should have the following installed.

### Required software

- **R**
- **RStudio** (strongly recommended, although not strictly required)

### Recommended versions

The app should generally work with recent versions of R. A good baseline is:

- **R 4.2 or newer**
- **RStudio Desktop** recent release

### Required R packages

The app installs missing packages automatically, but the user still needs an internet connection the first time if any package is not yet installed.

Required packages:

- `shiny`
- `DT`
- `shinyjs`
- `shinythemes`
- `htmltools`

---

## Files needed by the user

The user should have:

- the **R script** containing the app;
- a **CSV file** with the data to annotate.

---

## Expected input data

The app reads a CSV file and expects at least one text column.

### Minimum requirement

Your CSV must contain a column with the text to annotate. By default, the app expects this column to be called:

- `text`

If your text column has a different name, you can specify it in the field **“Text column name”** before loading the data.

### Optional context column

The app can also display a second column containing contextual information. By default, it expects:

- `context`

This is optional. If the specified context column does not exist, the app creates it as empty.

### One row = one unit of annotation

Each row of the CSV is treated as one item to review and code.

---

## Output produced by the app

As the user annotates the data, the app stores the coding results in additional columns. If these columns are not already present in the CSV, the app creates them automatically.

Main annotation columns:

- `issue`
- `policy_flag`
- `stance`
- `selected_at`
- `annotated_at`
- `uncertainty`
- `annotator`
- `not_sentence`
- `draft_flag`
- `issue2`
- `uncertainty2`
- `stance2`

The final output is an **annotated CSV file**.

---

## Categories used in the app

The topic choices currently available in the app are:

### Labour
- Labour: Undefined
- Labour: Salary or Pay gap
- Labour: Division of labour
- Labour: Labour rights and discrimination
- Labour: Other

### Welfare
- Welfare: Parental leave
- Welfare: Childcare and housework
- Welfare: Other care work
- Welfare: Healthcare
- Welfare: Education
- Welfare: Other

### Representation
- Repr.: Political representation and participation
- Repr.: Social representation and participation
- Repr.: Gender-neutral language
- Repr.: Gender mainstreaming
- Repr.: Other

### Rights, discrimination, and violence
- RDV: Reproductive rights and discrimination
- RDV: Family rights and discrimination
- RDV: Sexual and gender-based violence
- RDV: Immigration and citizenship
- RDV: Other

### Notions
- Notions: Feminism
- Notions: Patriarchy and heteronormativity
- Notions: LGBTQ+
- Notions: Other

---

## How to start the app

### Option 1: Run from RStudio

1. Open **RStudio**.
2. Open the app script file.
3. Make sure the full script is loaded in the editor.
4. Click **Source** or run the full script.
5. The Shiny app should open automatically.

### Option 2: Run from the R console

If the script is saved, for example, as `app.R`, you can run:

```r
source("app.R")
```

Because the script ends with:

```r
shinyApp(ui, server)
```

the app should launch once the script is sourced.

---

## First-time package installation

The script checks whether required packages are installed:

```r
want = c("shiny", "DT", "shinyjs", "shinythemes", "htmltools")
have = want %in% rownames(installed.packages())
if ( any(!have) ) { install.packages( want[!have] ) }
```

This means:

- if all packages are already installed, the app starts normally;
- if some packages are missing, R will try to install them automatically.

For this reason, the first run may take longer.

---

## Main structure of the interface

The app has two main areas:

### 1. Left sidebar
The sidebar is used for:

- loading the dataset;
- setting the text and context column names;
- entering the annotator name or ID;
- navigating between rows;
- setting the output directory;
- defining the output file name;
- saving or downloading the annotations.

### 2. Main panel
The main panel is used for:

- viewing annotation progress;
- reading the current context;
- reading the current text;
- coding the current row;
- reviewing the full dataset in a table.

---

## Step-by-step workflow

## 1. Load the data

In the left sidebar:

1. Click **Upload CSV** and choose your data file.
2. In **Text column name**, enter the name of the text column.
   - Default: `text`
3. In **Context column name (optional)**, enter the context column name.
   - Default: `context`
4. In **Annotator name / id**, type the annotator identifier.
5. Click **Load data**.

After loading:

- the app reads the CSV;
- it checks whether the specified text column exists;
- it creates any missing annotation columns;
- it sets the current position to the first row.

---

## 2. Read progress information

At the top of the main panel, the app shows a progress line such as:

- number of annotated rows;
- total number of rows;
- current row position.

This helps track how much work has been completed.

---

## 3. Read the context and text

If a context column is available and non-empty, the app shows it in the **Context** box.

The current text to annotate appears below that in the **Text to annotate** box.

---

## 4. Decide whether the item is a valid sentence

The app asks:

**Is this a valid sentence?**

Options:

- `sentence`
- `not a sentence`

### If you choose “sentence”
All coding inputs remain available.

### If you choose “not a sentence”
The app disables the other annotation inputs for that row and stores the row as not being a sentence. Topic, stance, uncertainty, and other content-related fields are cleared.

---

## 5. Code the primary topic

Under **Primary topic**, select one category from the dropdown menu.

This is stored in the `issue` column.

Because the input is a select box with search support, you can either:

- scroll through the list; or
- type to search for a category.

---

## 6. Code uncertainty

Use the uncertainty slider to record how certain you are about the topic choice.

Scale:

- `0` = certain
- `10` = very uncertain

This is stored in the `uncertainty` column.

---

## 7. Code stance

Use the stance slider for the primary topic.

Scale:

- `0` = against
- `10` = support

This is stored in the `stance` column.

### Unknown stance

If stance cannot be determined, click **Unknown** next to the slider.

---

## 8. Code whether the item is policy-related

Under **Policy-related**, choose:

- `policy`
- `other`

This is stored in the `policy_flag` column.

---

## 9. Add a second topic if needed

If the text contains more than one relevant topic, click:

**Add second topic**

This reveals a second annotation block.

You can then code:

- `issue2`
- `uncertainty2`
- `stance2`

If you click the button again, the second topic block is removed and the second-topic values for the current row are cleared.

---

## 10. Record the annotation

When the coding for the row is final, click:

**Record annotations**

This does the following:

- stores the current annotation;
- writes the annotator ID;
- writes the annotation timestamp;
- sets `draft_flag` to `FALSE`;
- moves automatically to the next row.

If the row was marked as **not a sentence**, the app stores that and clears the substantive coding fields for that row.

---

## 11. Save a draft instead of a final annotation

If you are not ready to finalise the row, click:

**Save draft**

This stores the current values but marks the row as a draft:

- `draft_flag = TRUE`

This is useful when:

- the coder is uncertain;
- the row needs to be revisited later;
- the coding is incomplete.

---

## 12. Clear the current row’s coding

If you want to remove all coding for the current row, click:

**Clear annotations for this row**

This clears:

- primary issue;
- policy flag;
- annotator;
- annotation timestamp;
- uncertainty;
- stance;
- selected timestamp;
- not-sentence flag;
- draft flag;
- second-topic fields.

---

## Navigation

The app provides several ways to move through the dataset.

### Buttons
- **Previous**
- **Next**

### Random order
- **Randomize order**

This shuffles the order in which rows are shown.

### Review table
At the bottom of the app there is a table showing the dataset and annotation columns. Clicking a row in the table moves the app to that position.

### Keyboard shortcuts
The app also includes shortcuts:

- **Left arrow**: previous row
- **Right arrow**: next row

There is also code for numeric shortcuts, but in the current version these are only practical for a limited number of categories and should not be relied on as the main workflow.

---

## Saving your work

The app supports several saving methods.

### 1. Manual save to a chosen directory

In the sidebar:

1. Set the output directory in **Output directory**.
2. Click **Set as output directory**.
3. Enter a file name in **File name**.
4. Click **Save annotations now**.

The app then writes the current dataset to a CSV file.

### 2. Temporary autosave

The app automatically writes a temporary file every 30 seconds after the data has been loaded.

This temporary file is named like:

- `yourfilename_tmp.csv`

This helps reduce the risk of losing work.

### 3. Download annotated CSV

You can also click **Download annotated CSV** to download the current annotated dataset directly from the Shiny session.

---

## How file paths work

The app allows the user to type or paste a save directory path.

When you click **Set as output directory**:

- if the folder exists, it is used;
- if the folder does not exist, the app attempts to create it.

The app also displays the effective save directory below the file name field.

---

## Timestamps recorded by the app

The app records two important timestamps.

### `selected_at`
This records the first time the row is shown to the user. It is only set once unless the row is cleared.

### `annotated_at`
This records the time when the row is saved as an annotation or draft.

These timestamps can be useful for workflow monitoring or annotation process analysis.

---

## Meaning of the main annotation fields

### `issue`
Primary topic selected by the annotator.

### `policy_flag`
Whether the item is policy-related.

### `stance`
Primary topic stance score.

### `uncertainty`
Uncertainty score for the primary topic.

### `issue2`
Second topic, if activated.

### `uncertainty2`
Uncertainty score for the second topic.

### `stance2`
Stance score for the second topic.

### `annotator`
Annotator name or ID entered in the sidebar.

### `not_sentence`
Whether the row was coded as not being a valid sentence.

### `draft_flag`
Whether the row was saved as a draft rather than final.

### `selected_at`
First display time.

### `annotated_at`
Time of most recent save or annotation action.

---

## Recommended workflow for users

A practical workflow is:

1. open the app;
2. load the CSV;
3. check that the text column name is correct;
4. check whether a context column is available;
5. enter your annotator ID;
6. review each row in order;
7. decide whether it is a sentence;
8. code primary topic, uncertainty, stance, and policy flag;
9. add a second topic only when needed;
10. save drafts when uncertain;
11. record final annotations when ready;
12. save the file regularly even though autosave exists;
13. export the final CSV when the work is complete.

---

## Common issues and solutions

## The app says the text column is missing
Cause:
- the name entered in **Text column name** does not match the actual CSV column name.

Solution:
- check the exact column name in the CSV;
- enter that exact name;
- reload the file.

## The context does not appear
Cause:
- the context column is empty or the column name is incorrect.

Solution:
- check the column name;
- verify that the column contains values.

## The app cannot save the file
Cause:
- invalid path;
- missing write permissions;
- file is open elsewhere;
- directory cannot be created.

Solution:
- choose a simpler directory;
- make sure you have write permission;
- close the file if it is already open in Excel or another program;
- try saving again.

## The packages do not install
Cause:
- no internet connection;
- repository access problem;
- restricted system permissions.

Solution:
- install packages manually in R;
- check internet access;
- ask local IT support if package installation is restricted.

Manual installation:

```r
install.packages(c("shiny", "DT", "shinyjs", "shinythemes", "htmltools"))
```

---

## Good practice recommendations

- Keep a backup copy of the original CSV before annotation.
- Use a clear annotator ID.
- Save manually at regular intervals even though autosave exists.
- Avoid renaming output columns during the annotation process.
- Do not edit the output CSV structure while the app is open.
- If multiple coders are working, keep separate files or establish a clear merging procedure.

---

## Suggested folder structure

A simple folder structure could look like this:

```text
project_folder/
├─ app.R
├─ data/
│  └─ input_data.csv
├─ output/
│  ├─ annotations_saved.csv
│  └─ annotations_saved_tmp.csv
└─ README.md
```

---

## Minimal example of how to launch the app

```r
source("app.R")
```

If everything is installed correctly, the app window should open.

---

## Summary

This app provides a structured environment for manual text annotation in R/Shiny. It supports:

- CSV-based input;
- one-item-at-a-time review;
- optional context display;
- sentence validity coding;
- topic coding with uncertainty and stance;
- optional second-topic annotation;
- draft saving;
- autosave;
- manual saving and download;
- review through an integrated table.

It is best used with a clean CSV input file, a clearly defined annotation protocol, and regular saving throughout the process.
