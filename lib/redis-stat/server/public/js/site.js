var history = [],
    max,
    rows,
    measures,
    colors,
    info,
    fade_dur,
    chart_options,
    stats_to_update = ['uptime_in_seconds', 'uptime_in_days']

var initialize = function(params) {
  measures = params.measures
  colors   = params.colors
  max      = params.max
  rows     = params.rows
  fade_dur = params.fade_dur
  info     = $("#info")
  chart_options = {
    chart1: {
      seriesDefaults: {
        showMarker: false,
        shadow: false
      },
      axesDefaults: {
        labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
        tickRenderer: $.jqplot.CanvasAxisTickRenderer
      },
      axes: {
        xaxis: {
          pad: 1,
          min: - max,
          tickOptions: { show: true }
        },
        yaxis: {
          label:'Commands/sec',
          min: 0,
          pad: 1.2
        }
      },
      grid: {
        borderWidth: 0.0,
        borderColor: '#ddd',
        background: '#ffffff',
        shadowAlpha: 0.03
      }
    },
    chart2: {
      seriesDefaults: {
        showMarker: false,
        shadow: false,
        fill: true
      },
      series: [
        { label: "user" },
        { label: "sys" }
      ],
      stackSeries: true,
      axesDefaults: {
        labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
        tickRenderer: $.jqplot.CanvasAxisTickRenderer,
        shadow: false
      },
      axes: {
        xaxis: {
          pad: 1,
          min: - max,
          tickOptions: { show: true }
        },
        yaxis: {
          label:'CPU usage',
          min: 0,
          pad: 1.0
        }
      },
      legend: {
        show: true,
        location: 'se'
      },
      grid: {
        borderWidth: 0.0,
        borderColor: '#ddd',
        background: '#ffffff',
        shadowAlpha: 0.03
      }
    },
    chart3: {
      seriesDefaults: {
        showMarker: false,
        shadow: false,
      },
      series: [
        { label: "used" },
        { label: "rss" }
      ],
      axesDefaults: {
        labelRenderer: $.jqplot.CanvasAxisLabelRenderer,
        tickRenderer: $.jqplot.CanvasAxisTickRenderer,
        shadow: false
      },
      axes: {
        xaxis: {
          pad: 1,
          min: - max,
          tickOptions: { show: true }
        },
        yaxis: {
          label:'Memory usage',
          min: 0,
          pad: 1.2,
          tickOptions: {
            formatString: "%dMB"
          }
        }
      },
      legend: {
        show: true,
        location: 'se'
      },
      grid: {
        borderWidth: 0.0,
        borderColor: '#ddd',
        background: '#ffffff',
        shadowAlpha: 0.03
      }
    },
  } // chart_options

  for (var i = 0; i < params.history.length; ++i) {
    appendToHistory(params.history[i])
    if (params.history.length - i <= rows)
      updateTable()
  }
  updatePlot()
}

var appendToHistory = function(json) {
  history.push(json)
  if (history.length > max) history.shift()
}

var updateTable = function() {
  var json = history[ history.length - 1 ],
      js   = json.static,
      jd   = json.dynamic

  // Instance information (mostly static)
  // for (stat in js) {
  for (var i = 0; i < stats_to_update.length; ++i) {
    var stat = stats_to_update[i]
    $("#" + stat).replaceWith(
      "<tr id='" + stat + "'><th>" + stat + "</th>" +
      js[stat].map(function(e) { return "<td>" + e + "</td>" }).join() +
      "</tr>"
    )
  }

  // Time-series tabular data
  var row = "<tr class='hide'>"
  for (var i = 0; i < measures.length; ++i) {
    var m = measures[i]
    row +=
      "<td class='" + colors[m] + "'>" +
      jd[m][0] +
      "</td>"
  }
  row += "</tr>"
  info.prepend(row)

  // Fade-in / cut-off
  infotr = $("#info tr")
  var infotr1 = infotr.first()
  infotr1.fadeIn(fade_dur)
  infotr1.find("td").css("font-style", "italic").css("text-decoration", "underline").css("font-weight", "bold")
  infotr1.next().find("td").css("font-style", "normal").css("text-decoration", "none").css("font-weight", "normal")
  var last = infotr.last()
  last.remove()
}

var updatePlot = function() {
  // Chart
  if (history.length > 0) {
    var offset = 1 - Math.min(max, history.length)

    // Commands/sec
    $.jqplot('chart1', [
      history.map(function(h, idx) {
        return [idx + offset, h.dynamic['total_commands_processed_per_second'][1] ] })
      ], chart_options.chart1).replot()

    // CPU usage
    $.jqplot('chart2', [
      history.map(function(h, idx) {
        return [idx + offset, h.dynamic['used_cpu_user'][1] ] }),
      history.map(function(h, idx) {
        return [idx + offset, h.dynamic['used_cpu_sys'][1] ] }),
      ], chart_options.chart2).replot()

    // Memory status
    $.jqplot('chart3', [
      history.map(function(h, idx) {
        return [idx + offset, h.dynamic['used_memory'][1] / 1024 / 1024 ] }),
      history.map(function(h, idx) {
        return [idx + offset, h.dynamic['used_memory_rss'][1] / 1024 / 1024 ] }),
      ], chart_options.chart3).replot()
  } else {
    $.jqplot('chart1', [[[-1, 0]]], chart_options.chart1)
    $.jqplot('chart2', [[[-1, 0]]], chart_options.chart2)
    $.jqplot('chart3', [[[0, 'MEM'], [0, 'RSS']]], chart_options.chart3)
  }
}
