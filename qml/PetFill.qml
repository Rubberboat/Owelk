import QtQuick
import QtQuick.Shapes

// A filled SVG path (the page's .f .w .e ... classes), with an optional outline of the same color.
ShapePath {
    id: part
    property string d
    property color color: "transparent"
    property real outline: 0
    fillColor: color
    strokeColor: outline > 0 ? color : "transparent"
    strokeWidth: outline > 0 ? outline : -1
    joinStyle: ShapePath.RoundJoin
    capStyle: ShapePath.RoundCap
    PathSvg { path: part.d }
}
