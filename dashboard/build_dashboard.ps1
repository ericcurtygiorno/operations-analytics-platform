$ErrorActionPreference = 'Stop'

$dashboardRoot = (Resolve-Path $PSScriptRoot).Path
$reportRoot = Join-Path $dashboardRoot 'operations-analytics-platform.Report'
$definitionRoot = Join-Path $reportRoot 'definition'
$pagesRoot = Join-Path $definitionRoot 'pages'
$resourcesRoot = Join-Path $reportRoot 'StaticResources\RegisteredResources'
$visualSchema = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.9.0/schema.json'
$pageSchema = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json'

if (-not ((Resolve-Path $reportRoot).Path.StartsWith($dashboardRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
    throw 'The report path escaped the dashboard root.'
}

function Write-JsonFile {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $content = ($Value | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    if ((Test-Path -LiteralPath $Path) -and ([System.IO.File]::ReadAllText($Path) -ceq $content)) {
        return
    }
    [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
}

function Get-StableId {
    param([string]$Seed)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant().Substring(0, 20)
    }
    finally { $sha.Dispose() }
}

function New-Literal {
    param([string]$Value)
    return @{ expr = @{ Literal = @{ Value = $Value } } }
}

function New-TextLiteral {
    param([string]$Value)
    return New-Literal ("'" + $Value.Replace("'", "''") + "'")
}

function New-BoolLiteral {
    param([bool]$Value)
    return New-Literal ($(if ($Value) { 'true' } else { 'false' }))
}

function New-NumberLiteral {
    param([double]$Value, [switch]$Integer)
    $text = $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    return New-Literal ($text + $(if ($Integer) { 'L' } else { 'D' }))
}

function New-FillLiteral {
    param([string]$Color)
    return @{ solid = @{ color = (New-TextLiteral $Color) } }
}

function New-MeasureProjection {
    param([string]$Name)
    return [ordered]@{
        field = @{ Measure = @{ Expression = @{ SourceRef = @{ Entity = '_Measures' } }; Property = $Name } }
        queryRef = "_Measures.$Name"
        nativeQueryRef = $Name
    }
}

function New-ColumnProjection {
    param([string]$Table, [string]$Column, [bool]$Active = $false)
    $projection = [ordered]@{
        field = @{ Column = @{ Expression = @{ SourceRef = @{ Entity = $Table } }; Property = $Column } }
        queryRef = "$Table.$Column"
        nativeQueryRef = $Column
    }
    if ($Active) { $projection.active = $true }
    return $projection
}

function New-CategoricalFilterConfig {
    param([string]$Name, [string]$Table, [string]$Column, [string]$Literal, [switch]$ExcludeValue)
    $inExpression = [ordered]@{
        In = [ordered]@{
            Expressions = @(@{ Column = @{ Expression = @{ SourceRef = @{ Source = 'filterSource' } }; Property = $Column } })
            Values = ,@(@{ Literal = @{ Value = $Literal } })
        }
    }
    $condition = if ($ExcludeValue) { @{ Not = @{ Expression = $inExpression } } } else { $inExpression }
    return @{
        filters = @(
            [ordered]@{
                name = $Name
                field = @{ Column = @{ Expression = @{ SourceRef = @{ Entity = $Table } }; Property = $Column } }
                type = 'Categorical'
                filter = @{
                    Version = 2
                    From = @(@{ Name = 'filterSource'; Entity = $Table; Type = 0 })
                    Where = @(@{ Condition = $condition })
                }
                howCreated = 'User'
            }
        )
    }
}

function New-Position {
    param([int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Z)
    return [ordered]@{ x = $X; y = $Y; z = $Z; height = $Height; width = $Width; tabOrder = $Z }
}

function New-ContainerObjects {
    param([string]$Title = '', [string]$Subtitle = '')
    $objects = [ordered]@{
        background = @(@{ properties = @{ show = (New-BoolLiteral $true); color = (New-FillLiteral '#111B2E'); transparency = (New-NumberLiteral 0) } })
        border = @(@{ properties = @{ show = (New-BoolLiteral $true); color = (New-FillLiteral '#24344D'); radius = (New-NumberLiteral 10); width = (New-NumberLiteral 1) } })
        visualHeader = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
        padding = @(@{ properties = @{ top = (New-NumberLiteral 10); bottom = (New-NumberLiteral 10); left = (New-NumberLiteral 12); right = (New-NumberLiteral 12) } })
    }
    if ($Title) {
        $objects.title = @(@{ properties = @{
            show = (New-BoolLiteral $true)
            text = (New-TextLiteral $Title)
            fontColor = (New-FillLiteral '#F5F7FA')
            fontSize = (New-NumberLiteral 14)
            bold = (New-BoolLiteral $true)
            fontFamily = (New-TextLiteral 'Segoe UI Semibold')
            background = (New-FillLiteral '#111B2E')
        } })
    }
    if ($Subtitle) {
        $objects.subTitle = @(@{ properties = @{
            show = (New-BoolLiteral $true)
            text = (New-TextLiteral $Subtitle)
            fontColor = (New-FillLiteral '#9FB0C7')
            fontSize = (New-NumberLiteral 10)
            fontFamily = (New-TextLiteral 'Segoe UI')
        } })
    }
    return $objects
}

function New-OverlayContainerObjects {
    return [ordered]@{
        background = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
        border = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
        visualHeader = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
        padding = @(@{ properties = @{ top = (New-NumberLiteral 0); bottom = (New-NumberLiteral 0); left = (New-NumberLiteral 0); right = (New-NumberLiteral 0) } })
    }
}

function Add-Visual {
    param([string]$PageName, [string]$Key, [object]$Visual)
    $visualName = Get-StableId "$PageName::$Key"
    $Visual.name = $visualName
    Write-JsonFile (Join-Path $pagesRoot "$PageName\visuals\$visualName\visual.json") $Visual
    return $visualName
}

function Add-Textbox {
    param([string]$PageName, [string]$Key, [string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$FontSize, [string]$Color, [bool]$Bold, [int]$Z)
    $style = [ordered]@{
        fontFamily = $(if ($Bold) { 'Segoe UI Semibold' } else { 'Segoe UI' })
        fontSize = "$($FontSize)px"
        color = $Color
    }
    if ($Bold) { $style.fontWeight = 'bold' }
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X $Y $Width $Height $Z)
        visual = [ordered]@{
            visualType = 'textbox'
            objects = @{ general = @(@{ properties = @{ paragraphs = @(@{ textRuns = @(@{ value = $Text; textStyle = $style }); horizontalTextAlignment = 'left' }) } }) }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                border = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                padding = @(@{ properties = @{ top = (New-NumberLiteral 0); bottom = (New-NumberLiteral 0); left = (New-NumberLiteral 0); right = (New-NumberLiteral 0) } })
            }
        }
    }
    Add-Visual $PageName $Key $visual | Out-Null
}

function Add-DecorativePanel {
    param(
        [string]$PageName, [string]$Key,
        [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [string]$FillColor, [int]$RoundEdge, [int]$Z
    )
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X $Y $Width $Height $Z)
        visual = [ordered]@{
            visualType = 'actionButton'
            objects = @{
                text = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                icon = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                fill = @(
                    @{ properties = @{ show = (New-BoolLiteral $true) } },
                    @{ properties = @{ fillColor = (New-FillLiteral $FillColor); transparency = (New-NumberLiteral 0) }; selector = @{ id = 'default' } }
                )
                outline = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                shape = @(
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded'); roundEdge = (New-NumberLiteral $RoundEdge -Integer) } },
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded') }; selector = @{ id = 'default' } }
                )
            }
            visualContainerObjects = (New-OverlayContainerObjects)
        }
        howCreated = 'InsertVisualButton'
    }
    Add-Visual $PageName $Key $visual | Out-Null
}

function Add-BrandMark {
    param([string]$PageName, [int]$Z)
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position 38 22 58 58 $Z)
        visual = [ordered]@{
            visualType = 'actionButton'
            objects = @{
                text = @(
                    @{ properties = @{ show = (New-BoolLiteral $true) } },
                    @{ properties = @{ text = (New-TextLiteral 'N'); fontFamily = (New-TextLiteral 'Segoe UI Semibold'); fontSize = (New-NumberLiteral 24); bold = (New-BoolLiteral $true); fontColor = (New-FillLiteral '#FFFFFF'); horizontalAlignment = (New-TextLiteral 'center') }; selector = @{ id = 'default' } }
                )
                icon = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                fill = @(
                    @{ properties = @{ show = (New-BoolLiteral $true) } },
                    @{ properties = @{ fillColor = (New-FillLiteral '#123349') }; selector = @{ id = 'default' } }
                )
                outline = @(@{ properties = @{ show = (New-BoolLiteral $true); lineColor = (New-FillLiteral '#36CFC9'); weight = (New-NumberLiteral 2) } })
                shape = @(
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded'); roundEdge = (New-NumberLiteral 10 -Integer) } },
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded') }; selector = @{ id = 'default' } }
                )
            }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                border = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                visualHeader = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
            }
        }
        howCreated = 'InsertVisualButton'
    }
    Add-Visual $PageName 'brand-mark' $visual | Out-Null
}

function Add-KPIBackground {
    param([string]$PageName, [string]$Key, [int]$X, [int]$Z)
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X 205 448 170 $Z)
        visual = [ordered]@{
            visualType = 'actionButton'
            objects = @{
                text = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                icon = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                fill = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                outline = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                shape = @(
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded'); roundEdge = (New-NumberLiteral 4 -Integer) } },
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded') }; selector = @{ id = 'default' } }
                )
            }
            visualContainerObjects = [ordered]@{
                background = @(@{ properties = @{
                    show = (New-BoolLiteral $true)
                    color = (New-FillLiteral '#111B2E')
                    transparency = (New-NumberLiteral 0)
                } })
                border = @(@{ properties = @{
                    show = (New-BoolLiteral $true)
                    color = (New-FillLiteral '#2B3D59')
                    radius = (New-NumberLiteral 22)
                    width = (New-NumberLiteral 1)
                } })
                visualHeader = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                padding = @(@{ properties = @{
                    top = (New-NumberLiteral 0)
                    bottom = (New-NumberLiteral 0)
                    left = (New-NumberLiteral 0)
                    right = (New-NumberLiteral 0)
                } })
            }
        }
        howCreated = 'InsertVisualButton'
    }
    Add-Visual $PageName "$Key-background" $visual | Out-Null
}

function Add-CardVisual {
    param(
        [string]$PageName, [string]$Key, [string]$Measure, [string]$TooltipMeasure, [string]$Label,
        [int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Color, [int]$FontSize, [int]$Z
    )
    $queryState = [ordered]@{
        Data = @{ projections = @((New-MeasureProjection $Measure)) }
        Tooltips = @{ projections = @((New-MeasureProjection $TooltipMeasure)) }
    }
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X $Y $Width $Height $Z)
        visual = [ordered]@{
            visualType = 'cardVisual'
            query = @{ queryState = $queryState }
            objects = @{
                value = @(@{ properties = @{
                    show = (New-BoolLiteral $true)
                    fontFamily = (New-TextLiteral 'Segoe UI Semibold')
                    fontSize = (New-NumberLiteral $FontSize)
                    bold = (New-BoolLiteral $true)
                    fontColor = (New-FillLiteral $Color)
                    horizontalAlignment = (New-TextLiteral 'center')
                    labelDisplayUnits = (New-NumberLiteral 0)
                }; selector = @{ id = 'default' } })
                label = @(@{ properties = @{
                    show = (New-BoolLiteral $true)
                    text = (New-TextLiteral $Label)
                    fontFamily = (New-TextLiteral 'Segoe UI')
                    fontSize = (New-NumberLiteral 9)
                    fontColor = (New-FillLiteral '#9FB0C7')
                    horizontalAlignment = (New-TextLiteral 'center')
                    position = (New-TextLiteral 'belowValue')
                }; selector = @{ id = 'default' } })
                fillCustom = @(@{ properties = @{ show = (New-BoolLiteral $false) }; selector = @{ id = 'default' } })
                outline = @(@{ properties = @{ show = (New-BoolLiteral $false) }; selector = @{ id = 'default' } })
            }
            visualContainerObjects = (New-OverlayContainerObjects)
        }
    }
    Add-Visual $PageName $Key $visual | Out-Null
}

function Add-KPIGroup {
    param([string]$PageName, [string]$Key, [string]$BaseMeasure, [string]$Label, [int]$X, [string]$Accent, [int]$Z)
    Add-KPIBackground $PageName $Key $X $Z
    Add-CardVisual $PageName "$Key-current" "$BaseMeasure | Current YTD" "$BaseMeasure | Definition" "$Label · Current YTD" ($X + 10) 210 428 94 $Accent 27 ($Z + 1)
    Add-CardVisual $PageName "$Key-prior" "$BaseMeasure | Prior YTD" "$BaseMeasure | Definition" 'Prior YTD' ($X + 16) 310 200 58 '#91A3BA' 15 ($Z + 2)
    Add-CardVisual $PageName "$Key-yoy" "$BaseMeasure | YoY" "$BaseMeasure | Definition" 'YoY vs prior' ($X + 232) 310 200 58 '#F5F7FA' 15 ($Z + 3)
    Add-KPIInfoIcon $PageName $Key "$BaseMeasure | Definition" $X $Accent ($Z + 4)
}

function Add-Chart {
    param(
        [string]$PageName, [string]$Key, [string]$Type, [string]$Title, [string]$Subtitle,
        [string]$CategoryTable, [string]$CategoryColumn, [string[]]$Measures,
        [int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$Color = '#36CFC9', [int]$Z,
        [string]$SeriesTable = '', [string]$SeriesColumn = '', [string[]]$TooltipMeasures = @(),
        [string]$FilterTable = '', [string]$FilterColumn = '', [string]$FilterLiteral = '',
        [switch]$ExcludeFilterValue
    )
    $measureProjections = @($Measures | ForEach-Object { New-MeasureProjection $_ })
    $queryState = [ordered]@{
        Category = @{ projections = @((New-ColumnProjection $CategoryTable $CategoryColumn $true)) }
        Y = @{ projections = $measureProjections }
    }
    if ($SeriesTable -and $SeriesColumn) {
        $queryState.Series = @{ projections = @((New-ColumnProjection $SeriesTable $SeriesColumn)) }
    }
    if ($TooltipMeasures.Count -gt 0) {
        $queryState.Tooltips = @{ projections = @($TooltipMeasures | ForEach-Object { New-MeasureProjection $_ }) }
    }
    $query = [ordered]@{ queryState = $queryState }
    if ($Type -ne 'lineChart') {
        $query.sortDefinition = @{ sort = @(@{ field = $measureProjections[0].field; direction = 'Descending' }); isDefaultSort = $true }
    }
    $chartObjects = [ordered]@{
        categoryAxis = @(@{ properties = @{ show = (New-BoolLiteral $true); fontFamily = (New-TextLiteral 'Segoe UI'); fontSize = (New-NumberLiteral 10); labelColor = (New-FillLiteral '#C8D4E3'); gridlineShow = (New-BoolLiteral $false); showAxisTitle = (New-BoolLiteral $false) } })
        valueAxis = @(@{ properties = @{ show = (New-BoolLiteral $true); fontFamily = (New-TextLiteral 'Segoe UI'); fontSize = (New-NumberLiteral 9); labelColor = (New-FillLiteral '#8395AE'); gridlineShow = (New-BoolLiteral $true); gridlineColor = (New-FillLiteral '#26364F'); gridlineTransparency = (New-NumberLiteral 20); showAxisTitle = (New-BoolLiteral $false) } })
    }
    if (-not ($SeriesTable -and $SeriesColumn)) {
        $chartObjects.dataPoint = @(@{ properties = @{ defaultColor = (New-FillLiteral $Color) } })
    }
    if ($Type -eq 'lineChart') {
        $chartObjects.legend = @(@{ properties = @{ show = (New-BoolLiteral $true); position = (New-TextLiteral 'Top'); fontFamily = (New-TextLiteral 'Segoe UI'); fontSize = (New-NumberLiteral 10); labelColor = (New-FillLiteral '#C8D4E3'); showTitle = (New-BoolLiteral $false) } })
        $chartObjects.shapes = @(@{ properties = @{ strokeWidth = (New-NumberLiteral 3); showMarker = (New-BoolLiteral $true); markerSize = (New-NumberLiteral 6) } })
    }
    else {
        $chartObjects.labels = @(@{ properties = @{ show = (New-BoolLiteral $true); fontFamily = (New-TextLiteral 'Segoe UI Semibold'); fontSize = (New-NumberLiteral 9); color = (New-FillLiteral '#E7EDF6'); labelPosition = (New-TextLiteral 'OutsideEnd'); labelPrecision = (New-NumberLiteral 1 -Integer) } })
    }
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X $Y $Width $Height $Z)
        visual = [ordered]@{
            visualType = $Type
            query = $query
            objects = $chartObjects
            visualContainerObjects = (New-ContainerObjects $Title $Subtitle)
        }
    }
    if ($FilterTable -and $FilterColumn -and $FilterLiteral) {
        $visual.filterConfig = New-CategoricalFilterConfig -Name "Filter$(Get-StableId "$PageName::$Key::$FilterColumn")" -Table $FilterTable -Column $FilterColumn -Literal $FilterLiteral -ExcludeValue:$ExcludeFilterValue
    }
    Add-Visual $PageName $Key $visual | Out-Null
}

function Add-Scatter {
    param(
        [string]$PageName, [string]$Key, [string]$Title, [string]$Subtitle,
        [string]$CategoryTable, [string]$CategoryColumn, [string]$XMeasure, [string]$YMeasure,
        [string]$SizeMeasure, [string[]]$TooltipMeasures,
        [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Z
    )
    $queryState = [ordered]@{
        Category = @{ projections = @((New-ColumnProjection $CategoryTable $CategoryColumn $true)) }
        X = @{ projections = @((New-MeasureProjection $XMeasure)) }
        Y = @{ projections = @((New-MeasureProjection $YMeasure)) }
        Size = @{ projections = @((New-MeasureProjection $SizeMeasure)) }
        Tooltips = @{ projections = @($TooltipMeasures | ForEach-Object { New-MeasureProjection $_ }) }
    }
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X $Y $Width $Height $Z)
        visual = [ordered]@{
            visualType = 'scatterChart'
            query = @{ queryState = $queryState }
            objects = @{
                categoryAxis = @(@{ properties = @{ show = (New-BoolLiteral $true); fontFamily = (New-TextLiteral 'Segoe UI'); fontSize = (New-NumberLiteral 9); labelColor = (New-FillLiteral '#8395AE'); gridlineShow = (New-BoolLiteral $true); gridlineColor = (New-FillLiteral '#26364F'); showAxisTitle = (New-BoolLiteral $true); axisTitleColor = (New-FillLiteral '#9FB0C7') } })
                valueAxis = @(@{ properties = @{ show = (New-BoolLiteral $true); fontFamily = (New-TextLiteral 'Segoe UI'); fontSize = (New-NumberLiteral 9); labelColor = (New-FillLiteral '#8395AE'); gridlineShow = (New-BoolLiteral $true); gridlineColor = (New-FillLiteral '#26364F'); showAxisTitle = (New-BoolLiteral $true); axisTitleColor = (New-FillLiteral '#9FB0C7') } })
                categoryLabels = @(@{ properties = @{ show = (New-BoolLiteral $true); color = (New-FillLiteral '#E7EDF6'); fontSize = (New-NumberLiteral 9) } })
                bubbles = @(@{ properties = @{ bubbleSize = (New-NumberLiteral 8); transparency = (New-NumberLiteral 12) } })
            }
            visualContainerObjects = (New-ContainerObjects $Title $Subtitle)
        }
    }
    Add-Visual $PageName $Key $visual | Out-Null
}

function Add-Table {
    param(
        [string]$PageName, [string]$Key, [string]$Title, [string]$Subtitle, [object[]]$Fields,
        [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$Z,
        [string]$FilterTable = '', [string]$FilterColumn = '', [string]$FilterLiteral = '', [switch]$ExcludeFilterValue
    )
    $projections = @()
    foreach ($field in $Fields) {
        if ($field.Kind -eq 'Measure') { $projections += New-MeasureProjection $field.Name }
        else { $projections += New-ColumnProjection $field.Table $field.Name }
    }
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X $Y $Width $Height $Z)
        visual = [ordered]@{
            visualType = 'tableEx'
            query = @{ queryState = @{ Values = @{ projections = $projections } } }
            objects = @{
                columnHeaders = @(@{ properties = @{ fontFamily = (New-TextLiteral 'Segoe UI Semibold'); fontSize = (New-NumberLiteral 10); bold = (New-BoolLiteral $true); fontColor = (New-FillLiteral '#F5F7FA'); backColor = (New-FillLiteral '#1B2A43'); autoSizeColumnWidth = (New-BoolLiteral $true); wordWrap = (New-BoolLiteral $true) } })
                values = @(@{ properties = @{ fontFamily = (New-TextLiteral 'Segoe UI'); fontSize = (New-NumberLiteral 9); fontColorPrimary = (New-FillLiteral '#DDE6F2'); backColorPrimary = (New-FillLiteral '#111B2E'); fontColorSecondary = (New-FillLiteral '#DDE6F2'); backColorSecondary = (New-FillLiteral '#152137'); wordWrap = (New-BoolLiteral $false) } })
                grid = @(@{ properties = @{ gridVertical = (New-BoolLiteral $false); gridHorizontal = (New-BoolLiteral $true); gridHorizontalColor = (New-FillLiteral '#26364F'); gridHorizontalWeight = (New-NumberLiteral 1); rowPadding = (New-NumberLiteral 6) } })
            }
            visualContainerObjects = (New-ContainerObjects $Title $Subtitle)
        }
    }
    if ($FilterTable -and $FilterColumn -and $FilterLiteral) {
        $visual.filterConfig = New-CategoricalFilterConfig -Name "Filter$(Get-StableId "$PageName::$Key::$FilterColumn")" -Table $FilterTable -Column $FilterColumn -Literal $FilterLiteral -ExcludeValue:$ExcludeFilterValue
    }
    Add-Visual $PageName $Key $visual | Out-Null
}

function Add-Slicer {
    param([string]$PageName, [string]$Key, [string]$Title, [string]$Table, [string]$Column, [int]$X, [int]$Y, [int]$Width, [int]$Z)
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position $X $Y $Width 80 $Z)
        visual = [ordered]@{
            visualType = 'slicer'
            query = @{ queryState = @{ Values = @{ projections = @((New-ColumnProjection $Table $Column)) } } }
            objects = @{
                data = @(@{ properties = @{ mode = (New-TextLiteral 'Dropdown') } })
                header = @(@{ properties = @{ show = (New-BoolLiteral $true); text = (New-TextLiteral $Title); fontFamily = (New-TextLiteral 'Segoe UI Semibold'); textSize = (New-NumberLiteral 10); fontColor = (New-FillLiteral '#DDE6F2'); background = (New-FillLiteral '#111B2E'); showRestatement = (New-BoolLiteral $false) } })
            }
            visualContainerObjects = (New-ContainerObjects)
        }
    }
    $visual.filterConfig = New-CategoricalFilterConfig `
        -Name "Filter$(Get-StableId "$PageName::$Key::nonblank")" `
        -Table $Table `
        -Column $Column `
        -Literal 'null' `
        -ExcludeValue
    Add-Visual $PageName $Key $visual | Out-Null
}

function Add-KPIInfoIcon {
    param(
        [string]$PageName, [string]$Key, [string]$TooltipMeasure,
        [int]$X, [string]$Color, [int]$Z
    )
    $infoProjection = New-MeasureProjection 'KPI Information Icon'
    $infoProjection.nativeQueryRef = 'Information'
    # Keep the icon in the card while removing the technical measure name from
    # the default tooltip. A zero-width display name avoids a visible label.
    $infoProjection.displayName = [string][char]0x200B
    $tooltipProjection = New-MeasureProjection $TooltipMeasure
    $tooltipProjection.nativeQueryRef = 'How it is calculated'
    $tooltipProjection.displayName = 'How it is calculated'
    $containerObjects = New-OverlayContainerObjects
    # PBIR does not consistently infer this setting from the Tooltips field
    # well, so enable the visual tooltip explicitly for every KPI info icon.
    $containerObjects.visualTooltip = @(@{ properties = @{
        show = (New-BoolLiteral $true)
    } })
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position ($X + 360) 211 72 56 $Z)
        visual = [ordered]@{
            visualType = 'cardVisual'
            query = @{ queryState = @{
                Data = @{ projections = @($infoProjection) }
                Tooltips = @{ projections = @($tooltipProjection) }
            } }
            objects = @{
                value = @(@{ properties = @{
                    show = (New-BoolLiteral $true)
                    fontFamily = (New-TextLiteral 'Segoe UI Symbol')
                    fontSize = (New-NumberLiteral 16)
                    bold = (New-BoolLiteral $true)
                    fontColor = (New-FillLiteral '#F5F7FA')
                    horizontalAlignment = (New-TextLiteral 'center')
                }; selector = @{ id = 'default' } })
                label = @(@{ properties = @{ show = (New-BoolLiteral $false) }; selector = @{ id = 'default' } })
                fillCustom = @(@{ properties = @{ show = (New-BoolLiteral $false) }; selector = @{ id = 'default' } })
                outline = @(@{ properties = @{ show = (New-BoolLiteral $false) }; selector = @{ id = 'default' } })
            }
            visualContainerObjects = $containerObjects
        }
    }
    Add-Visual $PageName "$Key-info" $visual | Out-Null
}

function Add-PageNavigator {
    param([string]$PageName, [int]$Z)
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position 40 125 1500 54 $Z)
        visual = [ordered]@{
            visualType = 'pageNavigator'
            objects = @{
                text = @(
                    @{ properties = @{ show = (New-BoolLiteral $true) } },
                    @{ properties = @{ fontFamily = (New-TextLiteral 'Segoe UI Semibold'); fontSize = (New-NumberLiteral 10); fontColor = (New-FillLiteral '#AFC0D5'); horizontalAlignment = (New-TextLiteral 'center'); verticalAlignment = (New-TextLiteral 'middle') }; selector = @{ id = 'default' } },
                    @{ properties = @{ fontColor = (New-FillLiteral '#FFFFFF'); bold = (New-BoolLiteral $true) }; selector = @{ id = 'selected' } },
                    @{ properties = @{ fontColor = (New-FillLiteral '#FFFFFF') }; selector = @{ id = 'hover' } }
                )
                fill = @(
                    @{ properties = @{ show = (New-BoolLiteral $true) } },
                    @{ properties = @{ fillColor = (New-FillLiteral '#111B2E') }; selector = @{ id = 'default' } },
                    @{ properties = @{ fillColor = (New-FillLiteral '#1D6F73') }; selector = @{ id = 'selected' } },
                    @{ properties = @{ fillColor = (New-FillLiteral '#1B2A43') }; selector = @{ id = 'hover' } }
                )
                shape = @(
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded'); roundEdge = (New-NumberLiteral 8 -Integer) } },
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded') }; selector = @{ id = 'default' } }
                )
                pages = @(@{ properties = @{ showHiddenPages = (New-BoolLiteral $true); showTooltipPages = (New-BoolLiteral $false); showByDefault = (New-BoolLiteral $true) } })
            }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                border = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                visualHeader = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                padding = @(@{ properties = @{ top = (New-NumberLiteral 0); bottom = (New-NumberLiteral 0); left = (New-NumberLiteral 0); right = (New-NumberLiteral 0) } })
            }
        }
    }
    Add-Visual $PageName 'page-navigator' $visual | Out-Null
}

function Add-ResetButton {
    param([string]$PageName, [string]$BookmarkName, [int]$Z)
    $visual = [ordered]@{
        '$schema' = $visualSchema
        name = ''
        position = (New-Position 1580 125 300 54 $Z)
        visual = [ordered]@{
            visualType = 'actionButton'
            objects = @{
                text = @(
                    @{ properties = @{ show = (New-BoolLiteral $true) } },
                    @{ properties = @{ text = (New-TextLiteral 'Reset filters'); fontFamily = (New-TextLiteral 'Segoe UI Semibold'); fontSize = (New-NumberLiteral 10); fontColor = (New-FillLiteral '#FFFFFF'); horizontalAlignment = (New-TextLiteral 'center') }; selector = @{ id = 'default' } }
                )
                icon = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                fill = @(
                    @{ properties = @{ show = (New-BoolLiteral $true) } },
                    @{ properties = @{ fillColor = (New-FillLiteral '#22324C') }; selector = @{ id = 'default' } },
                    @{ properties = @{ fillColor = (New-FillLiteral '#2D4466') }; selector = @{ id = 'hover' } }
                )
                outline = @(@{ properties = @{ show = (New-BoolLiteral $true); lineColor = (New-FillLiteral '#3A547A'); weight = (New-NumberLiteral 1) } })
                shape = @(
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded'); roundEdge = (New-NumberLiteral 8 -Integer) } },
                    @{ properties = @{ tileShape = (New-TextLiteral 'rectangleRounded') }; selector = @{ id = 'default' } }
                )
            }
            visualContainerObjects = @{
                background = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                border = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                visualHeader = @(@{ properties = @{ show = (New-BoolLiteral $false) } })
                visualLink = @(@{ properties = @{ show = (New-BoolLiteral $true); type = (New-TextLiteral 'Bookmark'); bookmark = (New-TextLiteral $BookmarkName) } })
            }
            drillFilterOtherVisuals = $true
        }
        howCreated = 'InsertVisualButton'
    }
    Add-Visual $PageName 'reset-button' $visual | Out-Null
}

function New-Page {
    param([string]$PageName, [string]$DisplayName, [string]$Subtitle, [string]$BookmarkName, [bool]$Hidden)
    $page = [ordered]@{
        '$schema' = $pageSchema
        name = $PageName
        displayName = $DisplayName
        displayOption = 'FitToPage'
        height = 1080
        width = 1920
        objects = @{
            background = @(@{ properties = @{ color = (New-FillLiteral '#08111F'); transparency = (New-NumberLiteral 0) } })
            outspace = @(@{ properties = @{ color = (New-FillLiteral '#08111F'); transparency = (New-NumberLiteral 0) } })
        }
    }
    if ($Hidden) { $page.visibility = 'HiddenInViewMode' }
    Write-JsonFile (Join-Path $pagesRoot "$PageName\page.json") $page
    New-Item -ItemType Directory -Force -Path (Join-Path $pagesRoot "$PageName\visuals") | Out-Null
    Add-DecorativePanel $PageName 'header-band' 0 0 1920 105 '#0B1626' 0 5
    Add-DecorativePanel $PageName 'header-accent' 0 0 8 105 '#1D9B9A' 0 6
    Add-DecorativePanel $PageName 'header-divider' 310 24 2 58 '#263A55' 0 7
    Add-BrandMark $PageName 100
    Add-Textbox $PageName 'brand-star' '✦' 78 13 24 24 15 '#FFB547' $true 101
    Add-Textbox $PageName 'brand-name' 'NORTHSTAR' 110 25 185 28 18 '#F5F7FA' $true 102
    Add-Textbox $PageName 'brand-caption' 'COMMERCE  /  ANALYTICS' 111 54 190 20 8 '#36CFC9' $true 103
    Add-Textbox $PageName 'title' $DisplayName 340 21 760 42 27 '#F5F7FA' $true 104
    Add-Textbox $PageName 'subtitle' $Subtitle 340 64 780 26 11 '#91A3BA' $false 105
    Add-Slicer $PageName 'year-slicer' 'Year' 'Dates' 'Year' 1180 18 170 115
    Add-Slicer $PageName 'month-slicer' 'Month' 'Dates' 'Month' 1365 18 190 120
    Add-Slicer $PageName 'service-slicer' 'Service type' 'Service Types' 'Service Type' 1570 18 310 125
    Add-PageNavigator $PageName 140
    Add-ResetButton $PageName $BookmarkName 150
}

if (Test-Path $pagesRoot) {
    Get-ChildItem -LiteralPath $pagesRoot -Force | Remove-Item -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $pagesRoot, $resourcesRoot | Out-Null

$pages = @(
    [ordered]@{ Name = '99cdbe4617baa4983db5'; Display = 'Executive Overview'; Subtitle = 'Service level, delivery volume, and business risk at a glance'; Bookmark = (Get-StableId 'bookmark-executive-reset'); Hidden = $false },
    [ordered]@{ Name = (Get-StableId 'page-operational-performance'); Display = 'Operational Performance'; Subtitle = 'Throughput, cycle time, and distribution-center execution'; Bookmark = (Get-StableId 'bookmark-operational-reset'); Hidden = $true },
    [ordered]@{ Name = (Get-StableId 'page-carriers-regions'); Display = 'Carriers & Regions'; Subtitle = 'Compare partner scale, cost, exceptions, and service performance'; Bookmark = (Get-StableId 'bookmark-carriers-reset'); Hidden = $true },
    [ordered]@{ Name = (Get-StableId 'page-exceptions-causes'); Display = 'Exceptions & Causes'; Subtitle = 'Identify the operational conditions driving retries and delivery failure'; Bookmark = (Get-StableId 'bookmark-exceptions-reset'); Hidden = $true },
    [ordered]@{ Name = (Get-StableId 'page-data-quality'); Display = 'Data Quality'; Subtitle = 'Make exclusions visible and keep SLA interpretation auditable'; Bookmark = (Get-StableId 'bookmark-quality-reset'); Hidden = $true }
)
foreach ($page in $pages) { New-Page $page.Name $page.Display $page.Subtitle $page.Bookmark $page.Hidden }

$kpiX = @(40, 504, 968, 1432)

$p = $pages[0].Name
Add-KPIGroup $p 'otd' 'On-Time Delivery Rate' 'On-Time Delivery Rate' $kpiX[0] '#36CFC9' 200
Add-KPIGroup $p 'shipments' 'Total Shipments' 'Total Shipments' $kpiX[1] '#62A7FF' 210
Add-KPIGroup $p 'delay' 'Average Delay (Late)' 'Average Delay (Late)' $kpiX[2] '#FFB547' 220
Add-KPIGroup $p 'exclusion' 'SLA Exclusion Rate' 'SLA Exclusion Rate' $kpiX[3] '#FF7A8A' 230
Add-Chart -PageName $p -Key 'monthly-otd' -Type 'lineChart' -Title 'On-time delivery rate by promised month' -Subtitle 'Monthly SLA performance per year' -CategoryTable 'Dates' -CategoryColumn 'Month' -Measures @('On-Time Delivery Rate') -X 40 -Y 400 -Width 880 -Height 640 -Z 300 -SeriesTable 'Dates' -SeriesColumn 'Year' -TooltipMeasures @('Total Shipments','SLA Eligible Shipments','Average Delay (Late)')
Add-Chart -PageName $p -Key 'carrier-ranking' -Type 'clusteredBarChart' -Title 'On-time delivery rate by carrier' -Subtitle 'SLA performance per carrier; delivered volume available in the tooltip' -CategoryTable 'Carriers' -CategoryColumn 'Carrier' -Measures @('On-Time Delivery Rate') -X 940 -Y 400 -Width 940 -Height 310 -Color '#62A7FF' -Z 310 -TooltipMeasures @('Delivered Shipments','Total Shipments','Average Delay (Late)','Exception Rate','Average Freight per Shipment')
Add-Chart -PageName $p -Key 'region-ranking' -Type 'clusteredBarChart' -Title 'On-time delivery rate by region' -Subtitle 'SLA performance per region; delivered volume available in the tooltip' -CategoryTable 'Locations' -CategoryColumn 'Region' -Measures @('On-Time Delivery Rate') -X 940 -Y 730 -Width 940 -Height 310 -Color '#8B7CFF' -Z 320 -TooltipMeasures @('Delivered Shipments','Total Shipments','Average Delay (Late)','Exception Rate','Average Freight per Shipment')

$p = $pages[1].Name
Add-KPIGroup $p 'delivered' 'Delivered Shipments' 'Delivered Shipments' $kpiX[0] '#36CFC9' 200
Add-KPIGroup $p 'open' 'Open Shipments' 'Open Shipments' $kpiX[1] '#62A7FF' 210
Add-KPIGroup $p 'order-ship' 'Average Order-to-Ship Hours' 'Order-to-Ship Hours' $kpiX[2] '#FFB547' 220
Add-KPIGroup $p 'ship-delivery' 'Average Ship-to-Delivery Days' 'Ship-to-Delivery Days' $kpiX[3] '#8B7CFF' 230
Add-Chart -PageName $p -Key 'monthly-volume' -Type 'lineChart' -Title 'Shipment volume by promised month' -Subtitle 'Distinct shipments per month and year' -CategoryTable 'Dates' -CategoryColumn 'Month' -Measures @('Total Shipments') -X 40 -Y 400 -Width 880 -Height 640 -Z 300 -SeriesTable 'Dates' -SeriesColumn 'Year' -TooltipMeasures @('Delivered Shipments','Open Shipments','On-Time Delivery Rate')
Add-Chart -PageName $p -Key 'dc-cycle' -Type 'clusteredBarChart' -Title 'Distribution-center cycle time' -Subtitle 'Average order-to-ship hours per distribution center' -CategoryTable 'Distribution Centers' -CategoryColumn 'Distribution Center' -Measures @('Average Order-to-Ship Hours') -X 940 -Y 400 -Width 940 -Height 310 -Color '#FFB547' -Z 310 -TooltipMeasures @('Total Shipments','On-Time Delivery Rate')
Add-Chart -PageName $p -Key 'service-cycle' -Type 'clusteredBarChart' -Title 'Delivery cycle by service type' -Subtitle 'Average ship-to-delivery days per service type' -CategoryTable 'Service Types' -CategoryColumn 'Service Type' -Measures @('Average Ship-to-Delivery Days') -X 940 -Y 730 -Width 940 -Height 310 -Color '#36CFC9' -Z 320 -TooltipMeasures @('Total Shipments','On-Time Delivery Rate')

$p = $pages[2].Name
Add-KPIGroup $p 'carrier-otd' 'On-Time Delivery Rate' 'On-Time Delivery Rate' $kpiX[0] '#36CFC9' 200
Add-KPIGroup $p 'carrier-volume' 'Total Shipments' 'Total Shipments' $kpiX[1] '#62A7FF' 210
Add-KPIGroup $p 'carrier-cost' 'Average Freight per Shipment' 'Freight per Shipment' $kpiX[2] '#FFB547' 220
Add-KPIGroup $p 'carrier-exceptions' 'Exception Rate' 'Exception Rate' $kpiX[3] '#FF7A8A' 230
Add-Table -PageName $p -Key 'carrier-scorecard' -Title 'Carrier scorecard' -Subtitle 'Volume, SLA, delay, exception, and freight exposure' -Fields @(
    @{ Kind = 'Column'; Table = 'Carriers'; Name = 'Carrier' },
    @{ Kind = 'Measure'; Name = 'Delivered Shipments' },
    @{ Kind = 'Measure'; Name = 'On-Time Delivery Rate' },
    @{ Kind = 'Measure'; Name = 'Average Delay (Late)' },
    @{ Kind = 'Measure'; Name = 'Exception Rate' },
    @{ Kind = 'Measure'; Name = 'Average Freight per Shipment' }
) -X 40 -Y 400 -Width 900 -Height 640 -Z 300
Add-Chart -PageName $p -Key 'carrier-volume-year' -Type 'clusteredColumnChart' -Title 'Delivered volume by carrier' -Subtitle 'Delivered shipments per carrier and year' -CategoryTable 'Carriers' -CategoryColumn 'Carrier' -Measures @('Delivered Shipments') -X 960 -Y 400 -Width 920 -Height 310 -Z 310 -SeriesTable 'Dates' -SeriesColumn 'Year' -TooltipMeasures @('On-Time Delivery Rate','Average Freight per Shipment','Exception Rate')
Add-Chart -PageName $p -Key 'region-exception' -Type 'clusteredBarChart' -Title 'Regional exception exposure' -Subtitle 'Exception rate per region with shipment volume in the tooltip' -CategoryTable 'Locations' -CategoryColumn 'Region' -Measures @('Exception Rate') -X 960 -Y 730 -Width 920 -Height 310 -Color '#8B7CFF' -Z 320 -TooltipMeasures @('Total Shipments','Delivered Shipments','On-Time Delivery Rate','Average Freight per Shipment')

$p = $pages[3].Name
Add-KPIGroup $p 'exception-shipments' 'Shipments with Exceptions' 'Exception Shipments' $kpiX[0] '#FF7A8A' 200
Add-KPIGroup $p 'exception-rate' 'Exception Rate' 'Exception Rate' $kpiX[1] '#FFB547' 210
Add-KPIGroup $p 'first-attempt' 'First-Attempt Success Rate' 'First-Attempt Success' $kpiX[2] '#36CFC9' 220
Add-KPIGroup $p 'p90-delay' 'P90 Delivery Delay' 'P90 Delivery Delay' $kpiX[3] '#8B7CFF' 230
Add-Chart -PageName $p -Key 'monthly-exception' -Type 'lineChart' -Title 'Exception rate by promised month' -Subtitle 'Monthly exception exposure per year' -CategoryTable 'Dates' -CategoryColumn 'Month' -Measures @('Exception Rate') -X 40 -Y 400 -Width 880 -Height 310 -Z 300 -SeriesTable 'Dates' -SeriesColumn 'Year' -TooltipMeasures @('Shipments with Exceptions','Total Shipments','First-Attempt Success Rate')
Add-Chart -PageName $p -Key 'failure-reason' -Type 'clusteredBarChart' -Title 'Shipments by latest failure reason' -Subtitle 'Exception shipments per recorded failure reason' -CategoryTable 'Deliveries' -CategoryColumn 'Failure Reason' -Measures @('Total Shipments') -X 40 -Y 730 -Width 880 -Height 310 -Color '#FF7A8A' -Z 310 -TooltipMeasures @('Exception Rate','Average Delay (Late)') -FilterTable 'Deliveries' -FilterColumn 'Exception Count' -FilterLiteral '0L' -ExcludeFilterValue
Add-Table -PageName $p -Key 'exception-detail' -Title 'Exception detail' -Subtitle 'Shipment-level context for root-cause investigation' -Fields @(
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Shipment ID' },
    @{ Kind = 'Column'; Table = 'Carriers'; Name = 'Carrier' },
    @{ Kind = 'Column'; Table = 'Locations'; Name = 'Region' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Failure Reason' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Delivery Attempts' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Delivery Delay Days' }
) -X 940 -Y 400 -Width 940 -Height 640 -Z 320 -FilterTable 'Deliveries' -FilterColumn 'Exception Count' -FilterLiteral '0L' -ExcludeFilterValue

$p = $pages[4].Name
Add-KPIGroup $p 'excluded' 'Excluded from SLA' 'Excluded from SLA' $kpiX[0] '#FF7A8A' 200
Add-KPIGroup $p 'orphan' 'Orphan Shipments' 'Orphan Shipments' $kpiX[1] '#FFB547' 210
Add-KPIGroup $p 'unknown' 'Unknown Carrier Shipments' 'Unknown Carrier' $kpiX[2] '#8B7CFF' 220
Add-KPIGroup $p 'timeline' 'Invalid Timeline Shipments' 'Invalid Timeline' $kpiX[3] '#62A7FF' 230
Add-Table -PageName $p -Key 'quality-detail' -Title 'Quality exception detail' -Subtitle 'Records excluded from SLA calculations and their quality flags' -Fields @(
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Shipment ID' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Order ID' },
    @{ Kind = 'Column'; Table = 'Carriers'; Name = 'Carrier' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Is Valid for SLA' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Is Orphan Order' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Is Unknown Carrier' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Is Delivery Before Shipment' },
    @{ Kind = 'Column'; Table = 'Deliveries'; Name = 'Is Delivered Without Timestamp' }
) -X 40 -Y 400 -Width 1050 -Height 640 -Z 300 -FilterTable 'Deliveries' -FilterColumn 'Is Valid for SLA' -FilterLiteral 'false'
Add-Chart -PageName $p -Key 'quality-by-carrier' -Type 'clusteredBarChart' -Title 'SLA exclusion rate by carrier' -Subtitle 'Excluded shipments as a share of volume per carrier' -CategoryTable 'Carriers' -CategoryColumn 'Carrier' -Measures @('SLA Exclusion Rate') -X 1110 -Y 400 -Width 770 -Height 310 -Color '#FF7A8A' -Z 310 -TooltipMeasures @('Excluded from SLA','Total Shipments','Shipments with Data Quality Issues')
Add-Chart -PageName $p -Key 'quality-trend' -Type 'lineChart' -Title 'SLA exclusion rate by promised month' -Subtitle 'Monthly quality exclusion trend per year' -CategoryTable 'Dates' -CategoryColumn 'Month' -Measures @('SLA Exclusion Rate') -X 1110 -Y 730 -Width 770 -Height 310 -Z 320 -SeriesTable 'Dates' -SeriesColumn 'Year' -TooltipMeasures @('Excluded from SLA','Total Shipments','Shipments with Data Quality Issues')

Write-JsonFile (Join-Path $pagesRoot 'pages.json') ([ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json'
    pageOrder = @($pages.Name)
    activePageName = $pages[0].Name
})

$bookmarkItems = @()
foreach ($page in $pages) {
    $bookmarkItems += @{ name = $page.Bookmark }
    $bookmark = [ordered]@{
        '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json'
        displayName = "Reset — $($page.Display)"
        name = $page.Bookmark
        options = @{ targetVisualNames = @(); suppressData = $false; suppressDisplay = $true; suppressActiveSection = $false; applyOnlyToTargetVisuals = $false }
        explorationState = @{ version = '1.3'; activeSection = $page.Name; filters = @{ byExpr = @() }; sections = @{ $($page.Name) = @{ filters = @{ byExpr = @() }; visualContainers = @{} } } }
    }
    Write-JsonFile (Join-Path $definitionRoot "bookmarks\$($page.Bookmark).bookmark.json") $bookmark
}
Write-JsonFile (Join-Path $definitionRoot 'bookmarks\bookmarks.json') ([ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmarksMetadata/1.0.0/schema.json'
    items = $bookmarkItems
})

$themeFile = 'NorthstarCommerce-c26a1006.json'
$theme = [ordered]@{
    name = $themeFile
    dataColors = @('#36CFC9', '#62A7FF', '#8B7CFF', '#FFB547', '#FF7A8A', '#A9E34B', '#F5F7FA')
    foreground = '#DDE6F2'
    foregroundNeutralSecondary = '#9FB0C7'
    foregroundNeutralTertiary = '#667892'
    background = '#111B2E'
    backgroundLight = '#152137'
    backgroundNeutral = '#1B2A43'
    tableAccent = '#36CFC9'
    good = '#36CFC9'
    neutral = '#FFB547'
    bad = '#FF7A8A'
    maximum = '#36CFC9'
    center = '#FFB547'
    minimum = '#FF7A8A'
    textClasses = @{
        title = @{ fontFace = 'Segoe UI Semibold'; color = '#F5F7FA'; fontSize = 14 }
        header = @{ fontFace = 'Segoe UI Semibold'; color = '#DDE6F2'; fontSize = 11 }
        label = @{ fontFace = 'Segoe UI'; color = '#DDE6F2'; fontSize = 10 }
        callout = @{ fontFace = 'Segoe UI Semibold'; color = '#F5F7FA'; fontSize = 28 }
    }
}
Write-JsonFile (Join-Path $resourcesRoot $themeFile) $theme

$report = [ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.3.0/schema.json'
    themeCollection = @{
        baseTheme = @{ name = 'Fluent2-CY26SU09'; reportVersionAtImport = @{ visual = '2.13.0'; report = '3.4.0'; page = '2.3.1' }; type = 'SharedResources' }
        customTheme = @{ name = $themeFile; reportVersionAtImport = @{ visual = '2.13.0'; report = '3.4.0'; page = '2.3.1' }; type = 'RegisteredResources' }
    }
    objects = @{ section = @(@{ properties = @{ verticalAlignment = (New-TextLiteral 'Top') } }) }
    resourcePackages = @(
        @{ name = 'SharedResources'; type = 'SharedResources'; items = @(@{ name = 'Fluent2-CY26SU09'; path = 'BaseThemes/Fluent2-CY26SU09.json'; type = 'BaseTheme' }) },
        @{ name = 'RegisteredResources'; type = 'RegisteredResources'; items = @(@{ name = $themeFile; path = $themeFile; type = 'CustomTheme' }) }
    )
    settings = @{ useStylableVisualContainerHeader = $true; exportDataMode = 'AllowSummarized'; defaultDrillFilterOtherVisuals = $true; allowChangeFilterTypes = $true; useEnhancedTooltips = $true; useDefaultAggregateDisplayName = $true }
}
Write-JsonFile (Join-Path $definitionRoot 'report.json') $report

$visualCount = (Get-ChildItem -LiteralPath $pagesRoot -Filter 'visual.json' -Recurse).Count
Write-Output "Dashboard generated: $($pages.Count) pages, $visualCount visuals, $($pages.Count) reset bookmarks."
