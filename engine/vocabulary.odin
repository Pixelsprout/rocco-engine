package engine

// Host names for the generated vocabulary types. The glue names each record
// by the path that reaches it from a provided function. A record shared by
// several paths takes the name of the first, so Vec3 is the pos of a Play's
// Place, Quat is a Collider's rot, a step result is a Roc_Init and Rgba is a
// Box background. A nominal type keeps its own name, so Element is
// Roc_VocabularyElement and Node is Roc_VocabularyNode. The glue names the
// fields of a Box and a Group _0 (the config, or the Group's id and Pose)
// and _1 (the children).
Config :: Roc_Init_Arg0
Launch :: Roc_Launch
Window :: Roc_Launch_Window
Msaa :: Roc_Launch_Window_Samples
Capacity :: Roc_Launch_Capacity
Init_Result :: Roc_Init
Input :: Roc_Step_Arg1
Step_Result :: Roc_Step
Command :: Roc_Init_Commands
Load_Command :: Roc_Init_Commands_Load
Play_Command :: Roc_Init_Commands_Play
Place :: Roc_Init_Commands_Play_At
Place_Tag :: Roc_Init_Commands_Play_At_Tag
Place_At :: Roc_Init_Commands_Play_At_At
Manifest_Entry :: Roc_Loaded_Arg2
Query_Results :: Roc_Step_Arg2
Contact :: Roc_Step_Arg2_Contacts
Ray_Hit :: Roc_Step_Arg2_Rays
Overlap_Hit :: Roc_Step_Arg2_Overlaps
Scene :: Roc_View
Node :: Roc_VocabularyNode
Node_Tag :: Roc_VocabularyNode_Tag
Group :: Roc_VocabularyNode_Group
Draw :: Roc_VocabularyNode_Draw
Collider :: Roc_VocabularyNode_Collider
Query :: Roc_View_Queries
Loop :: Roc_View_Loops
Query_Tag :: Roc_View_Queries_Tag
Query_Raycast :: Roc_View_Queries_Raycast
Query_Overlap :: Roc_View_Queries_Overlap
Light :: Roc_VocabularyNode_Light
Collider_Shape :: Roc_VocabularyNode_Collider_Shape
Collider_Shape_Tag :: Roc_VocabularyNode_Collider_Shape_Tag
Vec3 :: Roc_Init_Commands_Play_At_At_Pos
Quat :: Roc_VocabularyNode_Collider_Rot
Rgb :: Roc_VocabularyNode_Draw_Tint
Scene_Camera :: Roc_View_Camera
Cursor :: Roc_View_Cursor
Rgba :: Roc_VocabularyElement_Box_0_Background
Element :: Roc_VocabularyElement
Element_Tag :: Roc_VocabularyElement_Tag
Box_Config :: Roc_VocabularyElement_Box_0
Sizing :: Roc_VocabularyElement_Box_0_Height
Sizing_Tag :: Roc_VocabularyElement_Box_0_Height_Tag
Sizing_Range :: Roc_VocabularyElement_Box_0_Height_Fit
Pad :: Roc_VocabularyElement_Box_0_Pad
Direction :: Roc_VocabularyElement_Box_0_Direction
Child_Align :: Roc_VocabularyElement_Box_0_ChildAlign
Align :: Roc_VocabularyElement_Box_0_ChildAlign_X
Floating :: Roc_VocabularyElement_Box_0_Floating
Floating_Tag :: Roc_VocabularyElement_Box_0_Floating_Tag
Float_Config :: Roc_VocabularyElement_Box_0_Floating_Float
Attach_Point :: Roc_VocabularyElement_Box_0_Floating_Float_Attach
Text :: Roc_VocabularyElement_Text
Text_Wrap :: Roc_VocabularyElement_Text_Wrap
