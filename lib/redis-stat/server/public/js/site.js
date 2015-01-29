var hist = [],
    max,
    rows,
    measures,
    colors,
    info,
    fade_dur,
    chart_options,
    plot1, plot2, plot3;

var initialize = function(params) {
  // FIXME: Ruby symbol :sum is converted to a plain Javascript string 'sum',
  //        a host should not be named 'sum' at the moment
  selected = params.selected == null ? 'sum' : params.selected
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
          tickOptions: { show: false }
        },
        yaxis: {
          label:'Commands/sec',
          min: 0,
          pad: 1.2
        }
      },
      grid: {
        borderWidth: 1.0,
        borderColor: '#ddd',
        background: '#ffffff',
        shadow: false
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
          tickOptions: { show: false }
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
        borderWidth: 1.0,
        borderColor: '#ddd',
        background: '#ffffff',
        shadow: false
      }
    },
    chart3: {
      seriesDefaults: {
        showMarker: false,
        shadow: false,
      },
      series: [
        { label: "mem" },
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
          tickOptions: { show: false }
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
        borderWidth: 1.0,
        borderColor: '#ddd',
        background: '#ffffff',
        shadow: false
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
  if (hist.length == 0 || json.at > hist[ hist.length - 1 ].at) {
    hist.push(json)
    if (hist.length > max) hist.shift()
    return true
  } else {
    return false
  }
}

var updateTable = function() {
  var json = hist[ hist.length - 1 ],
      js   = json.static,
      jd   = json.dynamic

  // Instance information (mostly static)
  for (var stat in js) {
    $("#" + stat).replaceWith(
      "<tr id='" + stat + "'>" +
      js[stat].map(function(e) { return "<td>" + (e == null ? "<span class='label label-warning'>N/A</span>" : e) + "</td>" }).join() +
      "</tr>"
    )
  }

  // Time-series tabular data
  var row = "<tr class='hide'>"
  for (var i = 0; i < measures.length; ++i) {
    var m = measures[i]
    if (!jd[m].hasOwnProperty(selected)) return
    row +=
      "<td class='" + colors[m] + "'>" +
      jd[m][selected][0] +
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
  if (plot1 != undefined) plot1.destroy();
  if (plot2 != undefined) plot2.destroy();
  if (plot3 != undefined) plot3.destroy();

  var pluck = function(from) {
    if (from.hasOwnProperty(selected))
      return from[selected][1]
    else
      return 0
  }

  // Chart
  if (hist.length > 0) {
    var offset = 1 - Math.min(max, hist.length)

    // Commands/sec
    plot1 = $.jqplot('chart1', [
      hist.map(function(h, idx) {
        return [idx + offset, pluck(h.dynamic['total_commands_processed_per_second']) ] })
      ], chart_options.chart1);
    plot1.replot();

    // CPU usage
    plot2 = $.jqplot('chart2', [
      hist.map(function(h, idx) {
        return [idx + offset, pluck(h.dynamic['used_cpu_user']) ] }),
      hist.map(function(h, idx) {
        return [idx + offset, pluck(h.dynamic['used_cpu_sys']) ] }),
      ], chart_options.chart2);
    plot2.replot();

    // Memory status
    plot3 = $.jqplot('chart3', [
      hist.map(function(h, idx) {
        return [idx + offset, pluck(h.dynamic['used_memory']) / 1024 / 1024 ] }),
      hist.map(function(h, idx) {
        return [idx + offset, pluck(h.dynamic['used_memory_rss']) / 1024 / 1024 ] }),
      ], chart_options.chart3);
    plot3.replot();
  } else {
    plot1 = $.jqplot('chart1', [[[-1, 0]]], chart_options.chart1)
    plot2 = $.jqplot('chart2', [[[-1, 0]]], chart_options.chart2)
    plot3 = $.jqplot('chart3', [[[0, 'MEM'], [0, 'RSS']]], chart_options.chart3)
  }
}
