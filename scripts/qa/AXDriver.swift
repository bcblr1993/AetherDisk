import AppKit
import ApplicationServices
let args=CommandLine.arguments
let names=NSWorkspace.shared.runningApplications.filter{$0.localizedName=="AetherDisk"}
guard let app=names.first else { fatalError("AetherDisk not running") }
let root=AXUIElementCreateApplication(app.processIdentifier)
func get(_ e:AXUIElement,_ name:String)->CFTypeRef? { var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,name as CFString,&v) == .success ? v:nil }
func text(_ e:AXUIElement,_ name:String)->String { get(e,name).map{String(describing:$0)} ?? "" }
func walk(_ e:AXUIElement,_ depth:Int=0)->[AXUIElement] { if depth>25{return []};return [e]+((get(e,kAXChildrenAttribute) as? [AXUIElement]) ?? []).flatMap{walk($0,depth+1)} }
let nodes=walk(root)
if args.count>1 && args[1]=="windows" {
 for row in (CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]]) ?? [] where row[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier {
  print("\(row[kCGWindowNumber as String] ?? 0) | \(row[kCGWindowName as String] ?? "")")
 }
} else if args.count<2 || args[1]=="dump" {
 for e in nodes { print([text(e,kAXRoleAttribute),text(e,kAXTitleAttribute),text(e,kAXDescriptionAttribute),text(e,kAXValueAttribute),text(e,kAXIdentifierAttribute),text(e,kAXEnabledAttribute)].joined(separator:" | ")) }
} else if args[1]=="press" {
 let target=args[2]
 guard let e=nodes.first(where:{ ["AXButton","AXCheckBox","AXRadioButton","AXPopUpButton","AXMenuItem"].contains(text($0,kAXRoleAttribute)) && (text($0,kAXIdentifierAttribute)==target || text($0,kAXTitleAttribute)==target || text($0,kAXDescriptionAttribute)==target || text($0,kAXHelpAttribute)==target || text($0,kAXValueAttribute)==target) }) else {fatalError("Missing control: \(target)")}
 print(AXUIElementPerformAction(e,kAXPressAction as CFString).rawValue)
} else if args[1]=="focus" {
 app.activate(); usleep(300_000)
 let target=args[2];let e=nodes.first{ text($0,kAXIdentifierAttribute)==target || text($0,kAXPlaceholderValueAttribute)==target }!
 print(AXUIElementSetAttributeValue(e,kAXFocusedAttribute as CFString,kCFBooleanTrue).rawValue)
} else if args[1]=="set" {
 let target=args[2];let e=nodes.first{ text($0,kAXIdentifierAttribute)==target || text($0,kAXPlaceholderValueAttribute)==target }!
 print(AXUIElementSetAttributeValue(e,kAXValueAttribute as CFString,args[3] as CFString).rawValue)
}
