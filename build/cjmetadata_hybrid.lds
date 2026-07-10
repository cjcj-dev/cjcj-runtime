SECTIONS
{
  .cjmetadata ALIGN(16) :
  {
    PROVIDE_HIDDEN(__CJMetadataStart = .);
    *(.cjmetadata.*)
  }
}
INSERT AFTER .data;
