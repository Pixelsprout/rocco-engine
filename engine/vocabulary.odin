package engine

// Host names for the generated vocabulary types. The glue names each record
// by the path that reaches it from a provided function. A record shared by
// several paths takes the name of the first, so Vec3 is a Contact normal,
// a step result is a Roc_Init and Rgba is a Box background.
Config :: Roc_Init_Arg0
Init_Result :: Roc_Init
Input :: Roc_Step_Arg1
Step_Result :: Roc_Step
Command :: Roc_Init_Commands
Load_Command :: Roc_Init_Commands_Load
Manifest_Entry :: Roc_Loaded_Arg2
Contact :: Roc_Step_Arg2
Scene :: Roc_View
Draw :: Roc_View_Draws
Collider :: Roc_View_Colliders
Light :: Roc_View_Lights
Collider_Shape :: Roc_View_Colliders_Shape
Collider_Shape_Tag :: Roc_View_Colliders_Shape_Tag
Vec3 :: Roc_Step_Arg2_Normal
Quat :: Roc_View_Draws_Rot
Rgb :: Roc_View_Draws_Tint
Scene_Camera :: Roc_View_Camera
Cursor :: Roc_View_Cursor
Rgba :: Roc_View_Ui_Open_Background
Element :: Roc_View_Ui
Element_Tag :: Roc_View_Ui_Tag
Box_Config :: Roc_View_Ui_Open
Sizing :: Roc_View_Ui_Open_Height
Sizing_Tag :: Roc_View_Ui_Open_Height_Tag
Sizing_Range :: Roc_View_Ui_Open_Height_Fit
Pad :: Roc_View_Ui_Open_Pad
Direction :: Roc_View_Ui_Open_Direction
Child_Align :: Roc_View_Ui_Open_ChildAlign
Align :: Roc_View_Ui_Open_ChildAlign_X
Floating :: Roc_View_Ui_Open_Floating
Floating_Tag :: Roc_View_Ui_Open_Floating_Tag
Float_Config :: Roc_View_Ui_Open_Floating_Float
Attach_Point :: Roc_View_Ui_Open_Floating_Float_Attach
Text :: Roc_View_Ui_Text
Text_Wrap :: Roc_View_Ui_Text_Wrap
